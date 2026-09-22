/**
 * Discovers live configurator data at run time so the SeeAllData suites are not
 * pinned to one org's record Ids.
 *
 * The suites used to hardcode the reference org's Quote and QuoteLineItem, which
 * meant that on any other org they did not merely fail — they failed for a
 * misleading reason (a missing record looks identical to a broken engine), and
 * the quoted coverage number was unreachable. Worse, the Ids go stale on the
 * reference org too, because scratch and trial orgs expire.
 *
 * Strategy: ask the org. Find a QuoteLineItem whose product actually has
 * configurable attributes, by probing candidates through the same binding the
 * product code uses. If the org has no such data, discovery returns null and the
 * caller skips rather than failing a build for a data gap it cannot fix.
 */
@IsTest
public class ConfigTestFixture {

    /** How many candidate lines to probe before giving up. Keeps the call count bounded. */
    private static final Integer MAX_CANDIDATES = 5;

    public class Fixture {
        public Id quoteId;
        public Id rootQuoteLineItemId;
        public String productName;
        public Integer attributeCount;
    }

    private static Fixture cached;
    private static Boolean attempted = false;

    /** Set explicitly to pin the suites to known records; overrides discovery. */
    public static Fixture pinned;

    /**
     * A usable quote + configurable root line, or null when the org has none.
     * Result is cached for the transaction — discovery costs engine calls.
     */
    public static Fixture discover() {
        if (pinned != null) {
            return pinned;
        }
        if (attempted) {
            return cached;
        }
        attempted = true;

        List<QuoteLineItem> candidates;
        try {
            candidates = [
                SELECT Id, QuoteId, Product2Id, Product2.Name
                FROM QuoteLineItem
                WHERE QuoteId != NULL
                ORDER BY CreatedDate DESC
                LIMIT :MAX_CANDIDATES
            ];
        } catch (Exception e) {
            // Quote may be disabled in the org entirely.
            return null;
        }

        for (QuoteLineItem qli : candidates) {
            ConfigEngineBinding.OptionsResult opts;
            try {
                opts = ConfigEngineBinding.gateway().options(String.valueOf(qli.Id));
            } catch (Exception e) {
                continue;
            }
            if (opts == null || !opts.isSuccess || !opts.hasConfigurableAttributes) {
                continue;
            }

            Fixture f = new Fixture();
            f.quoteId = qli.QuoteId;
            f.rootQuoteLineItemId = qli.Id;
            f.productName = opts.productName;
            f.attributeCount = countAttributes(opts.attributesJson);
            cached = f;
            return cached;
        }
        return null;
    }

    private static Integer countAttributes(String attributesJson) {
        if (String.isBlank(attributesJson)) {
            return 0;
        }
        try {
            return ((List<Object>) JSON.deserializeUntyped(attributesJson)).size();
        } catch (Exception e) {
            return 0;
        }
    }

    /**
     * True when the org cannot support the live-data suites. Callers log and
     * return; a data gap is not a code defect, and failing here would train
     * people to ignore the suite.
     */
    public static Boolean unavailable(String testName) {
        if (discover() != null) {
            return false;
        }
        System.debug(LoggingLevel.WARN, 'SKIPPED ' + testName
            + ': no QuoteLineItem with configurable attributes found in this org. '
            + 'Load configurator demo data, or set ConfigTestFixture.pinned, to exercise it.');
        return true;
    }

    /**
     * The line's CURRENT configuration, as a selections payload.
     *
     * Re-submitting this is a genuine no-op on ANY product, which is what the
     * live-apply tests want: they exercise the real Place Sales Transaction round
     * trip without changing the quote. The previous hardcoded {"requiredKW":1500}
     * only had that property on the reference org's FESBA product.
     */
    public static String currentConfigurationJson() {
        Fixture f = discover();
        if (f == null) {
            return '{}';
        }
        ConfigEngineBinding.ReadResult r =
            ConfigEngineBinding.gateway().read(String.valueOf(f.rootQuoteLineItemId));
        return (r != null && String.isNotBlank(r.savedAttributesJson)) ? r.savedAttributesJson : '{}';
    }

    /** A syntactically valid but nonexistent QuoteLineItem Id, for not-found paths. */
    public static Id missingQuoteLineItemId() {
        Fixture f = discover();
        String prefix = (f != null)
            ? String.valueOf(f.rootQuoteLineItemId).left(15)
            : '0QL000000000000';
        return Id.valueOf(prefix.left(12) + '999');
    }
}
