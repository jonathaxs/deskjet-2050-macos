/*
 * ledm: reads the ink levels of an HP Deskjet 2050 J510 over USB.
 *
 * Shared by the CUPS filter (levels.c) and the macOS app (app/), so both read the printer the same way.
 */
#ifndef LEDM_H
#define LEDM_H

#ifdef __cplusplus
extern "C" {
#endif

#define LEDM_MAX_SUPPLIES 8

/* Results of ledm_read() below zero. */
#define LEDM_NOT_FOUND  -1 /* no HP printer with a status interface: off or unplugged */
#define LEDM_BUSY       -2 /* found, but could not open it (another program is using it) */
#define LEDM_NO_REPLY   -3 /* opened, but the printer did not answer */

typedef struct {
    char label[16];   /* K, CMY ... */
    char product[32]; /* 61, 61XL ... (the J510 does not send it) */
    char state[32];   /* newGenuineHP, genuineHP, nonHP, missing ... */
    int  level;       /* percent, or -2 when the printer does not know */
} ledm_supply;

typedef struct {
    int count;
    int low_threshold; /* percent the printer calls "low" (20 on the J510), 10 if it does not say */
    ledm_supply supplies[LEDM_MAX_SUPPLIES];
} ledm_levels;

/*
 * Asks the printer for /DevMgmt/ConsumableConfigDyn.xml and parses it into out.
 * Returns the number of supplies (0 or more) or one of the LEDM_* errors.
 * When raw is not NULL, *raw gets a copy of the whole HTTP reply (free it).
 * Messages go to stderr only when verbose is not zero.
 */
int ledm_read(ledm_levels *out, char **raw, int verbose);

/* English name of a supply: "Black", "Tri-color" ... */
const char *ledm_supply_name(const ledm_supply *s);

#ifdef __cplusplus
}
#endif

#endif
