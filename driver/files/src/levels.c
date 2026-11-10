/*
 * deskjet2050: reads the ink levels of an HP Deskjet 2050 J510 over USB and reports them to CUPS.
 *
 * The printer answers HTTP requests on a vendor-specific USB interface (class ff, subclass cc,
 * protocol 00). HPLIP calls this "LEDM over the FF/CC/0 channel" (status-type 11 in models.dat) and
 * reads the levels from /DevMgmt/ConsumableConfigDyn.xml. This program does the same with IOKit.
 *
 * It runs in three ways:
 *   deskjet2050                  in Terminal: prints the levels.
 *   as the CUPS filter of a print job: reports the levels (ATTR: marker-...), then runs hpcups with
 *                                the same arguments, so printing works exactly as before.
 *   as the CUPS filter of a command job (application/vnd.cups-command): only reports the levels.
 *                                macOS shows them in Printers & Scanners > Options & Supplies.
 *
 * Reading the levels never stops a print job: if the printer does not answer, the job goes on.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <ctype.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef HPCUPS_PATH
#define HPCUPS_PATH "/Library/Printers/DeskJet2050/Filter/hpcups"
#endif

#define HP_VENDOR_ID   0x03f0
#define LEDM_CLASS     0xff
#define LEDM_SUBCLASS  0xcc
#define LEDM_PROTOCOL  0x00
#define MAX_REPLY      (256 * 1024)
#define MAX_SUPPLIES   8

typedef IOUSBInterfaceInterface300 **usb_intf;

typedef struct {
    char label[16];   /* K, CMY ... */
    char product[32]; /* 61, 61XL ... */
    int  level;       /* percent, or -2 when the printer does not know */
} supply_t;

static int verbose;
static int low_threshold = 10; /* percent; the printer sends its own (20 on the J510) */

static void debug(const char *fmt, const char *arg)
{
    if (verbose)
        fprintf(stderr, fmt, arg);
}

/* ---------- USB ---------- */

static usb_intf open_ledm_interface(void)
{
    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBInterfaceClassName);
    if (!match)
        return NULL;
    int v;
    v = HP_VENDOR_ID;  CFDictionarySetValue(match, CFSTR(kUSBVendorID), CFNumberCreate(NULL, kCFNumberIntType, &v));
    v = LEDM_CLASS;    CFDictionarySetValue(match, CFSTR(kUSBInterfaceClass), CFNumberCreate(NULL, kCFNumberIntType, &v));
    v = LEDM_SUBCLASS; CFDictionarySetValue(match, CFSTR(kUSBInterfaceSubClass), CFNumberCreate(NULL, kCFNumberIntType, &v));
    v = LEDM_PROTOCOL; CFDictionarySetValue(match, CFSTR(kUSBInterfaceProtocol), CFNumberCreate(NULL, kCFNumberIntType, &v));

    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS)
        return NULL;

    usb_intf intf = NULL;
    io_service_t service;
    while (!intf && (service = IOIteratorNext(it))) {
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score;
        if (IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
                                              kIOCFPlugInInterfaceID, &plugin, &score) == kIOReturnSuccess && plugin) {
            (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&intf);
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(service);
        if (intf && (*intf)->USBInterfaceOpen(intf) != kIOReturnSuccess) {
            debug("deskjet2050: could not open the status interface%s\n", "");
            (*intf)->Release(intf);
            intf = NULL;
        }
    }
    IOObjectRelease(it);
    return intf;
}

static int find_pipes(usb_intf intf, UInt8 *in, UInt8 *out)
{
    UInt8 n = 0;
    *in = *out = 0;
    if ((*intf)->GetNumEndpoints(intf, &n) != kIOReturnSuccess)
        return -1;
    for (UInt8 p = 1; p <= n; p++) {
        UInt8 dir, num, type, interval;
        UInt16 size;
        if ((*intf)->GetPipeProperties(intf, p, &dir, &num, &type, &size, &interval) != kIOReturnSuccess)
            continue;
        if (type != kUSBBulk)
            continue;
        if (dir == kUSBIn && !*in)
            *in = p;
        else if (dir == kUSBOut && !*out)
            *out = p;
    }
    return (*in && *out) ? 0 : -1;
}

/* Sends one HTTP GET and returns the raw reply (headers + body), or NULL. */
static char *http_get(usb_intf intf, UInt8 in, UInt8 out, const char *path, size_t *len)
{
    char req[256];
    snprintf(req, sizeof(req), "GET %s HTTP/1.1\r\nAccept: text/plain\r\nHost:localhost\r\nUser-Agent:hplip\r\n\r\n", path);

    char *buf = malloc(MAX_REPLY + 1);
    if (!buf)
        return NULL;

    /* Drop anything left over from an earlier request that was not read to the end. */
    for (int i = 0; i < 8; i++) {
        UInt32 n = 4096;
        if ((*intf)->ReadPipeTO(intf, in, buf, &n, 100, 100) != kIOReturnSuccess || n == 0)
            break;
    }
    (*intf)->ClearPipeStallBothEnds(intf, in);

    if ((*intf)->WritePipeTO(intf, out, req, (UInt32)strlen(req), 3000, 3000) != kIOReturnSuccess) {
        free(buf);
        return NULL;
    }

    size_t got = 0;
    while (got < MAX_REPLY) {
        UInt32 n = (UInt32)((MAX_REPLY - got) < 16384 ? (MAX_REPLY - got) : 16384);
        IOReturn r = (*intf)->ReadPipeTO(intf, in, buf + got, &n, 3000, 5000);
        if (r != kIOReturnSuccess || n == 0)
            break;
        got += n;
        buf[got] = 0;
        if (strstr(buf, "</ccdyn:ConsumableConfigDyn>") || strstr(buf, "</ConsumableConfigDyn>"))
            break;
    }
    buf[got] = 0;
    *len = got;
    if (!got) {
        free(buf);
        return NULL;
    }
    return buf;
}

/* ---------- HTTP and XML ---------- */

/* Returns the body, decoding "Transfer-Encoding: chunked" in place when needed. */
static char *http_body(char *reply)
{
    char *body = strstr(reply, "\r\n\r\n");
    if (!body)
        return NULL;
    *body = 0;
    body += 4;

    int chunked = 0;
    for (char *p = reply; *p; p++)
        if (strncasecmp(p, "transfer-encoding:", 18) == 0 && strcasestr(p, "chunked"))
            chunked = 1;
    if (!chunked)
        return body;

    char *src = body, *dst = body;
    for (;;) {
        char *end;
        long size = strtol(src, &end, 16);
        if (end == src || size <= 0)
            break;
        src = strstr(end, "\r\n");
        if (!src)
            break;
        src += 2;
        size_t avail = strlen(src);
        if ((size_t)size > avail)
            size = (long)avail;
        memmove(dst, src, (size_t)size);
        dst += size;
        src += size;
        if (strncmp(src, "\r\n", 2) == 0)
            src += 2;
    }
    *dst = 0;
    return body;
}

/* Copies the text of the first <prefix:name> element in [start, end) into out. */
static int xml_value(const char *start, const char *end, const char *name, char *out, size_t size)
{
    size_t nlen = strlen(name);
    for (const char *p = start; p && p < end; p++) {
        p = strchr(p, '<');
        if (!p || p >= end)
            break;
        const char *tag = p + 1;
        if (*tag == '/')
            continue;
        const char *colon = tag;
        while (colon < end && *colon != ':' && *colon != '>' && *colon != ' ' && *colon != '/')
            colon++;
        const char *local = (*colon == ':') ? colon + 1 : tag;
        if (strncmp(local, name, nlen) != 0 || (local[nlen] != '>' && local[nlen] != ' '))
            continue;
        const char *v = strchr(local, '>');
        if (!v || v >= end)
            return -1;
        v++;
        const char *ve = strchr(v, '<');
        if (!ve || ve > end)
            return -1;
        size_t l = (size_t)(ve - v);
        if (l >= size)
            l = size - 1;
        memcpy(out, v, l);
        out[l] = 0;
        return 0;
    }
    return -1;
}

static const char *find_tag(const char *from, const char *name, int closing)
{
    char pat[64];
    snprintf(pat, sizeof(pat), "%s>", name);
    for (const char *p = from; (p = strstr(p, pat)); p++) {
        /* Walk back to the '<' and check it is <name>, <x:name>, </name> or </x:name>. */
        const char *lt = p;
        while (lt > from && *lt != '<' && *lt != '>')
            lt--;
        if (*lt != '<')
            continue;
        if ((lt[1] == '/') == closing)
            return lt;
    }
    return NULL;
}

static int parse_supplies(const char *xml, supply_t *s, int max)
{
    int count = 0;
    const char *p = xml;
    char thr[16];
    if (xml_value(xml, xml + strlen(xml), "ConsumableLowThreshold", thr, sizeof(thr)) == 0 && atoi(thr) > 0)
        low_threshold = atoi(thr);
    while (count < max && (p = find_tag(p, "ConsumableInfo", 0))) {
        const char *end = find_tag(p, "ConsumableInfo", 1);
        if (!end)
            break;
        char type[32] = "", state[32] = "", qstate[32] = "", level[16] = "";
        xml_value(p, end, "ConsumableTypeEnum", type, sizeof(type));
        if (strncmp(type, "ink", 3) == 0 || strncmp(type, "toner", 5) == 0) {
            supply_t *x = &s[count];
            memset(x, 0, sizeof(*x));
            xml_value(p, end, "ConsumableLabelCode", x->label, sizeof(x->label));
            if (xml_value(p, end, "ProductNumber", x->product, sizeof(x->product)) != 0)
                xml_value(p, end, "ConsumableSelectibilityNumber", x->product, sizeof(x->product));
            xml_value(p, end, "ConsumableState", state, sizeof(state));
            xml_value(p, end, "MeasuredQuantityState", qstate, sizeof(qstate));
            x->level = -2;
            if (strcmp(state, "missing") != 0 && xml_value(p, end, "ConsumablePercentageLevelRemaining", level, sizeof(level)) == 0) {
                x->level = atoi(level);
                if (x->level == 0 && strcmp(qstate, "unknown") == 0)
                    x->level = -2;
            }
            count++;
        }
        p = end + 1;
    }
    return count;
}

/* ---------- Reporting ---------- */

static const char *supply_name(const supply_t *s)
{
    if (strcmp(s->label, "K") == 0)
        return "Black";
    if (strcmp(s->label, "CMY") == 0)
        return "Tri-color";
    return s->label[0] ? s->label : "Ink";
}

static const char *supply_color(const supply_t *s)
{
    if (strcmp(s->label, "K") == 0)
        return "#000000";
    if (strcmp(s->label, "CMY") == 0)
        return "#00FFFF#FF00FF#FFFF00";
    if (strcmp(s->label, "C") == 0)
        return "#00FFFF";
    if (strcmp(s->label, "M") == 0)
        return "#FF00FF";
    if (strcmp(s->label, "Y") == 0)
        return "#FFFF00";
    return "none";
}

static void report_cups(const supply_t *s, int n)
{
    char colors[256] = "", levels[128] = "", names[256] = "", types[256] = "", low[64] = "", high[64] = "";
    for (int i = 0; i < n; i++) {
        const char *sep = i ? "," : "";
        char name[64], num[16];
        if (s[i].product[0])
            snprintf(name, sizeof(name), "%s%s ink (HP %s)", sep, supply_name(&s[i]), s[i].product);
        else
            snprintf(name, sizeof(name), "%s%s ink", sep, supply_name(&s[i]));
        strlcat(names, name, sizeof(names));
        snprintf(num, sizeof(num), "%s%d", sep, s[i].level);
        strlcat(levels, num, sizeof(levels));
        strlcat(colors, sep, sizeof(colors));
        strlcat(colors, supply_color(&s[i]), sizeof(colors));
        strlcat(types, sep, sizeof(types));
        strlcat(types, "ink-cartridge", sizeof(types));
        strlcat(low, sep, sizeof(low));
        snprintf(num, sizeof(num), "%d", low_threshold);
        strlcat(low, num, sizeof(low));
        strlcat(high, sep, sizeof(high));
        strlcat(high, "100", sizeof(high));
    }
    /* Names may have spaces, so they go in quotes. */
    char quoted[512] = "";
    for (int i = 0, start = 0; ; i++) {
        if (names[i] == ',' || names[i] == 0) {
            char part[96];
            snprintf(part, sizeof(part), "%s\"%.*s\"", start ? "," : "", i - start, names + start);
            strlcat(quoted, part, sizeof(quoted));
            if (!names[i])
                break;
            start = i + 1;
        }
    }
    fprintf(stderr, "ATTR: marker-colors=%s marker-levels=%s marker-names=%s marker-types=%s "
                    "marker-low-levels=%s marker-high-levels=%s\n",
            colors, levels, quoted, types, low, high);

    int any_low = 0, any_empty = 0;
    for (int i = 0; i < n; i++) {
        if (s[i].level == 0)
            any_empty = 1;
        else if (s[i].level > 0 && s[i].level <= low_threshold)
            any_low = 1;
    }
    fprintf(stderr, "STATE: %cmarker-supply-low-warning\n", any_low ? '+' : '-');
    fprintf(stderr, "STATE: %cmarker-supply-empty-warning\n", any_empty ? '+' : '-');
}

static void report_terminal(const supply_t *s, int n)
{
    for (int i = 0; i < n; i++) {
        printf("%-10s", supply_name(&s[i]));
        if (s[i].product[0])
            printf(" (HP %s)", s[i].product);
        if (s[i].level >= 0)
            printf(": %d%%\n", s[i].level);
        else
            printf(": unknown\n");
    }
}

/* Reads the levels. Returns the number of supplies found, or -1. */
static int read_levels(supply_t *s, int max, char **raw)
{
    usb_intf intf = open_ledm_interface();
    if (!intf) {
        debug("deskjet2050: printer status interface not found (is the printer on and plugged in?)%s\n", "");
        return -1;
    }
    int n = -1;
    UInt8 in, out;
    if (find_pipes(intf, &in, &out) == 0) {
        size_t len;
        char *reply = http_get(intf, in, out, "/DevMgmt/ConsumableConfigDyn.xml", &len);
        if (reply) {
            if (raw)
                *raw = strdup(reply);
            char *body = http_body(reply);
            if (body)
                n = parse_supplies(body, s, max);
            free(reply);
        }
    }
    (*intf)->USBInterfaceClose(intf);
    (*intf)->Release(intf);
    return n;
}

int main(int argc, char *argv[])
{
    supply_t s[MAX_SUPPLIES];
    const char *ctype = getenv("CONTENT_TYPE");
    int as_filter = (argc == 6 || argc == 7) && getenv("DEVICE_URI");

    if (!as_filter) {
        int raw = argc > 1 && strcmp(argv[1], "--raw") == 0;
        verbose = 1;
        char *xml = NULL;
        int n = read_levels(s, MAX_SUPPLIES, raw ? &xml : NULL);
        if (raw && xml)
            fputs(xml, stdout);
        if (n <= 0) {
            fprintf(stderr, "Could not read the ink levels.\n");
            return 1;
        }
        if (!raw)
            report_terminal(s, n);
        return 0;
    }

    verbose = getenv("DESKJET2050_DEBUG") != NULL;

    if (ctype && strcmp(ctype, "application/vnd.cups-command") == 0) {
        /* The only command we offer is ReportLevels; read the file so CUPS sees it consumed. */
        char line[256];
        FILE *in = argc == 7 ? fopen(argv[6], "r") : stdin;
        while (in && fgets(line, sizeof(line), in))
            ;
        if (in && in != stdin)
            fclose(in);
        int n = read_levels(s, MAX_SUPPLIES, NULL);
        if (n > 0)
            report_cups(s, n);
        else
            fprintf(stderr, "INFO: Could not read the ink levels\n");
        return 0;
    }

    int n = read_levels(s, MAX_SUPPLIES, NULL);
    if (n > 0)
        report_cups(s, n);
    fflush(stderr);
    execv(HPCUPS_PATH, argv);
    fprintf(stderr, "ERROR: could not run %s: %s\n", HPCUPS_PATH, strerror(errno));
    return 1;
}
