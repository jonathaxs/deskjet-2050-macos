/*
 * ledm: reads the ink levels of an HP Deskjet 2050 J510 over USB (see ledm.h).
 *
 * The printer answers HTTP requests on a vendor-specific USB interface (class ff, subclass cc,
 * protocol 00). HPLIP calls this "LEDM over the FF/CC/0 channel" (status-type 11 in models.dat) and
 * reads the levels from /DevMgmt/ConsumableConfigDyn.xml. This file does the same with IOKit, which
 * works without root.
 */
#include "ledm.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#define HP_VENDOR_ID   0x03f0
#define LEDM_CLASS     0xff
#define LEDM_SUBCLASS  0xcc
#define LEDM_PROTOCOL  0x00
#define MAX_REPLY      (256 * 1024)

typedef IOUSBInterfaceInterface300 **usb_intf;

static int verbose;

static void debug(const char *msg)
{
    if (verbose)
        fprintf(stderr, "deskjet2050: %s\n", msg);
}

/* ---------- USB ---------- */

static void set_number(CFMutableDictionaryRef dict, CFStringRef key, int value)
{
    CFNumberRef n = CFNumberCreate(NULL, kCFNumberIntType, &value);
    CFDictionarySetValue(dict, key, n);
    CFRelease(n);
}

/* Opens the status interface. *found tells whether the printer was there at all. */
static usb_intf open_ledm_interface(int *found)
{
    *found = 0;
    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBInterfaceClassName);
    if (!match)
        return NULL;
    set_number(match, CFSTR(kUSBVendorID), HP_VENDOR_ID);
    set_number(match, CFSTR(kUSBInterfaceClass), LEDM_CLASS);
    set_number(match, CFSTR(kUSBInterfaceSubClass), LEDM_SUBCLASS);
    set_number(match, CFSTR(kUSBInterfaceProtocol), LEDM_PROTOCOL);

    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS)
        return NULL;

    usb_intf intf = NULL;
    io_service_t service;
    while (!intf && (service = IOIteratorNext(it))) {
        *found = 1;
        IOCFPlugInInterface **plugin = NULL;
        SInt32 score;
        if (IOCreatePlugInInterfaceForService(service, kIOUSBInterfaceUserClientTypeID,
                                              kIOCFPlugInInterfaceID, &plugin, &score) == kIOReturnSuccess && plugin) {
            (*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&intf);
            IODestroyPlugInInterface(plugin);
        }
        IOObjectRelease(service);
        if (intf && (*intf)->USBInterfaceOpen(intf) != kIOReturnSuccess) {
            debug("could not open the status interface");
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
static char *http_get(usb_intf intf, UInt8 in, UInt8 out, const char *path)
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

static void parse_supplies(const char *xml, ledm_levels *out)
{
    const char *p = xml;
    char thr[16];
    if (xml_value(xml, xml + strlen(xml), "ConsumableLowThreshold", thr, sizeof(thr)) == 0 && atoi(thr) > 0)
        out->low_threshold = atoi(thr);
    while (out->count < LEDM_MAX_SUPPLIES && (p = find_tag(p, "ConsumableInfo", 0))) {
        const char *end = find_tag(p, "ConsumableInfo", 1);
        if (!end)
            break;
        char type[32] = "", qstate[32] = "", level[16] = "";
        xml_value(p, end, "ConsumableTypeEnum", type, sizeof(type));
        if (strncmp(type, "ink", 3) == 0 || strncmp(type, "toner", 5) == 0) {
            ledm_supply *x = &out->supplies[out->count];
            memset(x, 0, sizeof(*x));
            xml_value(p, end, "ConsumableLabelCode", x->label, sizeof(x->label));
            if (xml_value(p, end, "ProductNumber", x->product, sizeof(x->product)) != 0)
                xml_value(p, end, "ConsumableSelectibilityNumber", x->product, sizeof(x->product));
            xml_value(p, end, "ConsumableState", x->state, sizeof(x->state));
            xml_value(p, end, "MeasuredQuantityState", qstate, sizeof(qstate));
            x->level = -2;
            if (strcmp(x->state, "missing") != 0 && xml_value(p, end, "ConsumablePercentageLevelRemaining", level, sizeof(level)) == 0) {
                x->level = atoi(level);
                if (x->level == 0 && strcmp(qstate, "unknown") == 0)
                    x->level = -2;
            }
            out->count++;
        }
        p = end + 1;
    }
}

/* ---------- Public ---------- */

const char *ledm_supply_name(const ledm_supply *s)
{
    if (strcmp(s->label, "K") == 0)
        return "Black";
    if (strcmp(s->label, "CMY") == 0)
        return "Tri-color";
    return s->label[0] ? s->label : "Ink";
}

int ledm_read(ledm_levels *out, char **raw, int verbose_flag)
{
    verbose = verbose_flag;
    memset(out, 0, sizeof(*out));
    out->low_threshold = 10;
    if (raw)
        *raw = NULL;

    int found;
    usb_intf intf = open_ledm_interface(&found);
    if (!intf) {
        if (!found)
            debug("printer status interface not found (is the printer on and plugged in?)");
        return found ? LEDM_BUSY : LEDM_NOT_FOUND;
    }
    int result = LEDM_NO_REPLY;
    UInt8 in, out_pipe;
    if (find_pipes(intf, &in, &out_pipe) == 0) {
        char *reply = http_get(intf, in, out_pipe, "/DevMgmt/ConsumableConfigDyn.xml");
        if (reply) {
            if (raw)
                *raw = strdup(reply);
            char *body = http_body(reply);
            if (body) {
                parse_supplies(body, out);
                result = out->count;
            }
            free(reply);
        }
    }
    if (result == LEDM_NO_REPLY)
        debug("the printer did not answer");
    (*intf)->USBInterfaceClose(intf);
    (*intf)->Release(intf);
    return result;
}
