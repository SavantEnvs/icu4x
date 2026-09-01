// mayhem/kat — known-answer-test probe for the icu4x integration.
//
// Fixed inputs -> exact asserted values, lifted directly from icu_calendar's own
// doctests (components/calendar/src/date.rs, options.rs, duration.rs) so the
// expected values are the project's OWN documented ground truth, not invented.
//
// Prints one `KATn_...=value` line per check plus a final `KAT_ALL_PASS` /
// `KAT_SOME_FAIL` marker. mayhem/test.sh greps every line verbatim: a neutered
// binary (sabotage shim _exit(0)s before printing anything) yields NO matching
// output, so test.sh fails loudly instead of passing on a silent no-op.
use icu_calendar::options::{DateAddOptions, DateDifferenceOptions};
use icu_calendar::types::{DateDuration, Weekday};
use icu_calendar::Date;

fn main() {
    let mut ok = true;

    // KAT1 — construction + weekday.
    // Source: components/calendar/src/lib.rs module doc.
    //   Date::try_new_iso(1992, 9, 2) -> weekday() == Weekday::Wednesday,
    //   era_year().year == 1992.
    let d1 = Date::try_new_iso(1992, 9, 2).expect("KAT1: construct 1992-09-02");
    let weekday = d1.weekday();
    let era_year = d1.era_year().year;
    println!("KAT1_WEEKDAY={weekday:?}");
    println!("KAT1_ERA_YEAR={era_year}");
    if weekday != Weekday::Wednesday || era_year != 1992 {
        ok = false;
        println!("KAT1_FAIL");
    }

    // KAT2 — date arithmetic (add), default Overflow::Constrain.
    // Source: components/calendar/src/options.rs DateAddOptions doc.
    //   2025-10-31 + 1 month (constrain) == 2025-11-30 (no day 31 in November).
    let base = Date::try_new_iso(2025, 10, 31).expect("KAT2: construct 2025-10-31");
    let added = base
        .try_added_with_options(DateDuration::for_months(1), DateAddOptions::default())
        .expect("KAT2: add 1 month");
    let (ay, am, ad) = (
        added.era_year().year,
        added.month().ordinal,
        added.day_of_month().0,
    );
    println!("KAT2_ADDED_YMD={ay:04}-{am:02}-{ad:02}");
    if (ay, am, ad) != (2025, 11, 30) {
        ok = false;
        println!("KAT2_FAIL");
    }

    // KAT3 — date difference (until), default largest_unit == Days.
    // Source: components/calendar/src/options.rs DateDifferenceOptions doc.
    //   2025-03-31 .. 2026-05-15 == DateDuration::for_days(410).
    let from = Date::try_new_iso(2025, 3, 31).expect("KAT3: construct 2025-03-31");
    let to = Date::try_new_iso(2026, 5, 15).expect("KAT3: construct 2026-05-15");
    let diff = from
        .try_until_with_options(&to, DateDifferenceOptions::default())
        .expect("KAT3: until");
    println!("KAT3_DIFF_DAYS={}", diff.days);
    println!("KAT3_DIFF_IS_NEGATIVE={}", diff.is_negative);
    if diff != DateDuration::for_days(410) {
        ok = false;
        println!("KAT3_FAIL");
    }

    if ok {
        println!("KAT_ALL_PASS");
        std::process::exit(0);
    } else {
        println!("KAT_SOME_FAIL");
        std::process::exit(1);
    }
}
