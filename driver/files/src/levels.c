/*
 * deskjet2050: reads the ink levels of an HP Deskjet 2050 J510 over USB and reports them to CUPS.
 *
 * The reading itself is in ledm.c, shared with the macOS app.
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
#include "ledm.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef HPCUPS_PATH
#define HPCUPS_PATH "/Library/Printers/DeskJet2050/Filter/hpcups"
#endif

typedef ledm_supply supply_t;

/* ---------- Reporting ---------- */

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

static void report_cups(const ledm_levels *lv)
{
    const supply_t *s = lv->supplies;
    int n = lv->count;
    char colors[256] = "", levels[128] = "", names[256] = "", types[256] = "", low[64] = "", high[64] = "";
    for (int i = 0; i < n; i++) {
        const char *sep = i ? "," : "";
        char name[64], num[16];
        if (s[i].product[0])
            snprintf(name, sizeof(name), "%s%s ink (HP %s)", sep, ledm_supply_name(&s[i]), s[i].product);
        else
            snprintf(name, sizeof(name), "%s%s ink", sep, ledm_supply_name(&s[i]));
        strlcat(names, name, sizeof(names));
        snprintf(num, sizeof(num), "%s%d", sep, s[i].level);
        strlcat(levels, num, sizeof(levels));
        strlcat(colors, sep, sizeof(colors));
        strlcat(colors, supply_color(&s[i]), sizeof(colors));
        strlcat(types, sep, sizeof(types));
        strlcat(types, "ink-cartridge", sizeof(types));
        strlcat(low, sep, sizeof(low));
        snprintf(num, sizeof(num), "%d", lv->low_threshold);
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
        else if (s[i].level > 0 && s[i].level <= lv->low_threshold)
            any_low = 1;
    }
    fprintf(stderr, "STATE: %cmarker-supply-low-warning\n", any_low ? '+' : '-');
    fprintf(stderr, "STATE: %cmarker-supply-empty-warning\n", any_empty ? '+' : '-');
}

static void report_terminal(const ledm_levels *lv)
{
    const supply_t *s = lv->supplies;
    int n = lv->count;
    for (int i = 0; i < n; i++) {
        printf("%-10s", ledm_supply_name(&s[i]));
        if (s[i].product[0])
            printf(" (HP %s)", s[i].product);
        if (s[i].level >= 0)
            printf(": %d%%\n", s[i].level);
        else
            printf(": unknown\n");
    }
}

int main(int argc, char *argv[])
{
    ledm_levels lv;
    const char *ctype = getenv("CONTENT_TYPE");
    int as_filter = (argc == 6 || argc == 7) && getenv("DEVICE_URI");

    if (!as_filter) {
        int raw = argc > 1 && strcmp(argv[1], "--raw") == 0;
        char *xml = NULL;
        int n = ledm_read(&lv, raw ? &xml : NULL, 1);
        if (raw && xml)
            fputs(xml, stdout);
        free(xml);
        if (n <= 0) {
            fprintf(stderr, "Could not read the ink levels.\n");
            return 1;
        }
        if (!raw)
            report_terminal(&lv);
        return 0;
    }

    int verbose = getenv("DESKJET2050_DEBUG") != NULL;

    if (ctype && strcmp(ctype, "application/vnd.cups-command") == 0) {
        /* The only command we offer is ReportLevels; read the file so CUPS sees it consumed. */
        char line[256];
        FILE *in = argc == 7 ? fopen(argv[6], "r") : stdin;
        while (in && fgets(line, sizeof(line), in))
            ;
        if (in && in != stdin)
            fclose(in);
        if (ledm_read(&lv, NULL, verbose) > 0)
            report_cups(&lv);
        else
            fprintf(stderr, "INFO: Could not read the ink levels\n");
        return 0;
    }

    if (ledm_read(&lv, NULL, verbose) > 0)
        report_cups(&lv);
    fflush(stderr);
    execv(HPCUPS_PATH, argv);
    fprintf(stderr, "ERROR: could not run %s: %s\n", HPCUPS_PATH, strerror(errno));
    return 1;
}
