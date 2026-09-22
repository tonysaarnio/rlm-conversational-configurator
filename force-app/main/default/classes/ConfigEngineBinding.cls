/**
 * ConfigEngineBinding — the single place this repo talks to the org's RLM
 * configurator engine.
 *
 * WHY THIS EXISTS
 * ---------------
 * The engine services are org-resident and NOT part of this repo, and their
 * names are not universal: an org may carry them under a namespace or a local
 * prefix (e.g. RLM_AI_ProductAttributeService). Previously ConfigEngineController
 * named those classes as compile-time types, so porting the POC to such an org
 * meant hand-editing every reference — and the SaveGateway seam did not help,
 * because it published an engine type (ProductAttributeSaveService.SaveOutput)
 * in its own signature, insulating tests but not orgs.
 *
 * All three engine services are @InvocableMethod actions, so they can be reached
 * by NAME. This class does that, which means:
 *
 *   - nothing in this repo references an engine type at compile time;
 *   - the names live in the RLM_Config_Engine_Binding__mdt custom metadata type,
 *     so an admin re-points them with no code change and no redeploy of Apex;
 *   - the results cross into repo-owned DTOs, so the seam actually insulates.
 *
 * PLATFORM NOTES (learned the hard way, verified against a live org)
 * ------------------------------------------------------------------
 *   - Invocable parameters are typed String. Passing an Id fails with
 *     INVALID_INPUT ("Unable to convert value ... to Apex type String"), so every
 *     id is coerced with String.valueOf() before being set.
 *   - createCustomAction() does NOT validate the name; an unknown action fails
 *     only at invoke(), as a result with MISSING_RECORD. Always check isSuccess()
 *     before reading outputs — getOutputParameters() is null on failure.
 */
public with sharing class ConfigEngineBinding {

    // ---------------------------------------------------------------- DTOs --
    // Repo-owned. No engine type crosses this boundary.

    public class OptionsResult {
        public Boolean isSuccess = false;
        public String  errorMessage;
        public String  productName;
        public Boolean hasConfigurableAttributes = false;
        public String  attributesJson;
        public String  attributeSummary;
    }

    public class SaveResult {
        public Boolean isSuccess = false;
        public Boolean isValid = false;
        public String  errorMessage;
        public String  savedAttributesJson;
        public String  validationErrorsJson;
    }

    public class ReadResult {
        public Boolean isSuccess = false;
        public String  errorMessage;
        public String  savedAttributesJson;
        public String  configurationSummary;
    }

    // ------------------------------------------------------------- Gateway --
    /** The seam. Tests swap in a stub; nothing here mentions an engine type. */
    public interface Gateway {
        OptionsResult options(String quoteLineItemId);
        SaveResult    save(String quoteId, String quoteLineItemId, String attributeSelectionsJson);
        ReadResult    read(String quoteLineItemId);
    }

    @TestVisible
    private static Gateway gatewayInstance = new InvocableGateway();

    /** Swap the engine gateway (tests only). Returns the previous instance. */
    @TestVisible
    private static Gateway setGateway(Gateway g) {
        Gateway previous = gatewayInstance;
        gatewayInstance = g;
        return previous;
    }

    public static Gateway gateway() {
        return gatewayInstance;
    }

    // ------------------------------------------------- Action-name binding --

    // Used when the custom metadata record is missing, so a default-named org
    // works with no configuration at all.
    @TestVisible private static final String DEFAULT_OPTIONS_ACTION = 'ProductAttributeService';
    @TestVisible private static final String DEFAULT_SAVE_ACTION    = 'ProductAttributeSaveService';
    @TestVisible private static final String DEFAULT_READ_ACTION    = 'ProductAttributeReadService';

    // Tests set this to exercise re-pointing without depending on org records.
    @TestVisible private static RLM_Config_Engine_Binding__mdt overrideBinding;

    // Resolved lazily and cached. A plain backing field, not a property: an Apex
    // property whose getter reads its own name recurses until the stack blows.
    private static RLM_Config_Engine_Binding__mdt resolvedBinding;
    private static Boolean bindingResolved = false;

    private static RLM_Config_Engine_Binding__mdt binding() {
        if (overrideBinding != null) {
            return overrideBinding;
        }
        if (!bindingResolved) {
            // Null when the record is absent — every caller falls back to a default,
            // so a default-named org needs no custom metadata at all.
            resolvedBinding = RLM_Config_Engine_Binding__mdt.getInstance('Default');
            bindingResolved = true;
        }
        return resolvedBinding;
    }

    private static String actionName(String configured, String fallback) {
        return String.isNotBlank(configured) ? configured.trim() : fallback;
    }

    @TestVisible
    private static String optionsAction() {
        RLM_Config_Engine_Binding__mdt b = binding();
        return actionName(b == null ? null : b.Options_Action__c, DEFAULT_OPTIONS_ACTION);
    }

    @TestVisible
    private static String saveAction() {
        RLM_Config_Engine_Binding__mdt b = binding();
        return actionName(b == null ? null : b.Save_Action__c, DEFAULT_SAVE_ACTION);
    }

    @TestVisible
    private static String readAction() {
        RLM_Config_Engine_Binding__mdt b = binding();
        return actionName(b == null ? null : b.Read_Action__c, DEFAULT_READ_ACTION);
    }

    // --------------------------------------------------- Invocable gateway --

    /** Calls the engine by action name. The only place invoke() is used. */
    private class InvocableGateway implements Gateway {

        public OptionsResult options(String quoteLineItemId) {
            OptionsResult r = new OptionsResult();
            Invocation inv = call(optionsAction(), new Map<String, Object>{
                'quoteLineItemId' => quoteLineItemId
            });
            r.isSuccess = inv.isSuccess;
            r.errorMessage = inv.errorMessage;
            if (!inv.isSuccess) {
                return r;
            }
            r.productName = str(inv.outputs.get('productName'));
            r.hasConfigurableAttributes = bool(inv.outputs.get('hasConfigurableAttributes'));
            r.attributesJson = str(inv.outputs.get('attributesJson'));
            r.attributeSummary = str(inv.outputs.get('attributeSummary'));
            // The engine reports its own business-level failure in-band.
            if (inv.outputs.containsKey('isSuccess') && !bool(inv.outputs.get('isSuccess'))) {
                r.isSuccess = false;
                r.errorMessage = str(inv.outputs.get('errorMessage'));
            }
            return r;
        }

        public SaveResult save(String quoteId, String quoteLineItemId, String attributeSelectionsJson) {
            SaveResult r = new SaveResult();
            Invocation inv = call(saveAction(), new Map<String, Object>{
                'quoteId'                 => quoteId,
                'quoteLineItemId'         => quoteLineItemId,
                'attributeSelectionsJson' => attributeSelectionsJson
            });
            if (!inv.isSuccess) {
                r.errorMessage = inv.errorMessage;
                return r;
            }
            r.isSuccess = bool(inv.outputs.get('isSuccess'));
            r.isValid = bool(inv.outputs.get('isValid'));
            r.errorMessage = str(inv.outputs.get('errorMessage'));
            r.savedAttributesJson = str(inv.outputs.get('savedAttributesJson'));
            r.validationErrorsJson = str(inv.outputs.get('validationErrorsJson'));
            return r;
        }

        public ReadResult read(String quoteLineItemId) {
            ReadResult r = new ReadResult();
            Invocation inv = call(readAction(), new Map<String, Object>{
                'quoteLineItemId' => quoteLineItemId
            });
            if (!inv.isSuccess) {
                r.errorMessage = inv.errorMessage;
                return r;
            }
            r.isSuccess = bool(inv.outputs.get('isSuccess'));
            r.errorMessage = str(inv.outputs.get('errorMessage'));
            r.savedAttributesJson = str(inv.outputs.get('savedAttributesJson'));
            r.configurationSummary = str(inv.outputs.get('configurationSummary'));
            return r;
        }
    }

    // ------------------------------------------------------------ plumbing --

    private class Invocation {
        Boolean isSuccess = false;
        String errorMessage;
        Map<String, Object> outputs = new Map<String, Object>();
    }

    private static Invocation call(String actionName, Map<String, Object> params) {
        Invocation out = new Invocation();
        try {
            Invocable.Action action = Invocable.Action.createCustomAction('apex', actionName);
            for (String key : params.keySet()) {
                // Invocable inputs are String-typed; an Id value is rejected outright.
                Object v = params.get(key);
                action.setInvocationParameter(key, v == null ? null : String.valueOf(v));
            }

            List<Invocable.Action.Result> results = action.invoke();
            if (results == null || results.isEmpty()) {
                out.errorMessage = 'Engine action "' + actionName + '" returned no result.';
                return out;
            }

            Invocable.Action.Result result = results[0];
            if (!result.isSuccess()) {
                out.errorMessage = describe(actionName, result);
                return out;
            }

            Map<String, Object> outputs = result.getOutputParameters();
            out.outputs = (outputs == null) ? new Map<String, Object>() : outputs;
            out.isSuccess = true;
            return out;

        } catch (Exception e) {
            out.errorMessage = 'Engine action "' + actionName + '" failed: ' + e.getMessage();
            return out;
        }
    }

    /** Turn the platform's error list into something a user can act on. */
    private static String describe(String actionName, Invocable.Action.Result result) {
        List<String> parts = new List<String>();
        Boolean missing = false;
        for (Invocable.Action.Error err : result.getErrors()) {
            parts.add(err.getMessage());
            if ('MISSING_RECORD'.equals(err.getCode())) {
                missing = true;
            }
        }
        String detail = parts.isEmpty() ? 'no detail returned' : String.join(parts, '; ');
        if (missing) {
            // By far the most likely misconfiguration, so name the remedy.
            return 'Engine action "' + actionName + '" was not found in this org. '
                 + 'Set the correct name on the RLM_Config_Engine_Binding__mdt "Default" record '
                 + '(Setup -> Custom Metadata Types). Detail: ' + detail;
        }
        return 'Engine action "' + actionName + '" failed: ' + detail;
    }

    private static String str(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    private static Boolean bool(Object o) {
        return o instanceof Boolean ? (Boolean) o : false;
    }
}
