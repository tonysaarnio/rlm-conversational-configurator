/**
 * Seam-based coverage for ConfigEngineBinding. No live engine, no Einstein, no
 * agent credits — the point is that name resolution and failure handling behave
 * predictably on an org where the engine may not exist at all.
 */
@IsTest
private class ConfigEngineBindingTest {

    // ------------------------------------------------- action-name binding --

    @IsTest
    static void defaultsApplyWhenNoBindingRecordExists() {
        ConfigEngineBinding.overrideBinding = null;

        // Whatever the org holds, a blank/absent record must fall back to the
        // stock engine names rather than to null.
        Test.startTest();
        String options = ConfigEngineBinding.optionsAction();
        String save = ConfigEngineBinding.saveAction();
        String read = ConfigEngineBinding.readAction();
        Test.stopTest();

        System.assert(String.isNotBlank(options), 'options action must never resolve blank');
        System.assert(String.isNotBlank(save), 'save action must never resolve blank');
        System.assert(String.isNotBlank(read), 'read action must never resolve blank');
    }

    @IsTest
    static void overrideRepointsEveryAction() {
        ConfigEngineBinding.overrideBinding = new RLM_Config_Engine_Binding__mdt(
            Options_Action__c = 'ACME_ProductAttributeService',
            Save_Action__c    = 'ACME_ProductAttributeSaveService',
            Read_Action__c    = 'ACME_ProductAttributeReadService'
        );

        Test.startTest();
        System.assertEquals('ACME_ProductAttributeService', ConfigEngineBinding.optionsAction());
        System.assertEquals('ACME_ProductAttributeSaveService', ConfigEngineBinding.saveAction());
        System.assertEquals('ACME_ProductAttributeReadService', ConfigEngineBinding.readAction());
        Test.stopTest();

        ConfigEngineBinding.overrideBinding = null;
    }

    @IsTest
    static void blankOverrideFieldFallsBackToDefault() {
        // A half-filled record must not produce an empty action name.
        ConfigEngineBinding.overrideBinding = new RLM_Config_Engine_Binding__mdt(
            Options_Action__c = '   ',
            Save_Action__c    = 'ACME_Save',
            Read_Action__c    = null
        );

        Test.startTest();
        System.assertEquals(ConfigEngineBinding.DEFAULT_OPTIONS_ACTION,
            ConfigEngineBinding.optionsAction(), 'whitespace must fall back');
        System.assertEquals('ACME_Save', ConfigEngineBinding.saveAction());
        System.assertEquals(ConfigEngineBinding.DEFAULT_READ_ACTION,
            ConfigEngineBinding.readAction(), 'null must fall back');
        Test.stopTest();

        ConfigEngineBinding.overrideBinding = null;
    }

    @IsTest
    static void configuredNameIsTrimmed() {
        ConfigEngineBinding.overrideBinding = new RLM_Config_Engine_Binding__mdt(
            Options_Action__c = '  Padded_Service  '
        );

        Test.startTest();
        System.assertEquals('Padded_Service', ConfigEngineBinding.optionsAction(),
            'a name pasted with stray whitespace must still resolve');
        Test.stopTest();

        ConfigEngineBinding.overrideBinding = null;
    }

    // --------------------------------------------- unknown-action handling --

    @IsTest
    static void unknownActionIsReportedNotThrown() {
        // The real failure mode on a new org: the engine exists under another
        // name. Every entry point must return a failed DTO carrying an
        // actionable message, never throw and never return null.
        ConfigEngineBinding.overrideBinding = new RLM_Config_Engine_Binding__mdt(
            Options_Action__c = 'No_Such_Action_ConfigEngineBindingTest',
            Save_Action__c    = 'No_Such_Action_ConfigEngineBindingTest',
            Read_Action__c    = 'No_Such_Action_ConfigEngineBindingTest'
        );

        Test.startTest();
        ConfigEngineBinding.OptionsResult o = ConfigEngineBinding.gateway().options('0QL000000000000');
        ConfigEngineBinding.SaveResult    s = ConfigEngineBinding.gateway().save('0Q0000000000000', '0QL000000000000', '{}');
        ConfigEngineBinding.ReadResult    r = ConfigEngineBinding.gateway().read('0QL000000000000');
        Test.stopTest();

        System.assertNotEquals(null, o, 'options must return a DTO');
        System.assertEquals(false, o.isSuccess, 'unknown action must not report success');
        System.assert(String.isNotBlank(o.errorMessage), 'failure must carry a message');
        System.assert(o.errorMessage.contains('No_Such_Action_ConfigEngineBindingTest'),
            'message should name the action that could not be found: ' + o.errorMessage);

        System.assertEquals(false, s.isSuccess, 'save must not report success');
        System.assert(String.isNotBlank(s.errorMessage));

        System.assertEquals(false, r.isSuccess, 'read must not report success');
        System.assert(String.isNotBlank(r.errorMessage));

        ConfigEngineBinding.overrideBinding = null;
    }

    // ------------------------------------------------------- gateway seam --

    private class StubGateway implements ConfigEngineBinding.Gateway {
        public ConfigEngineBinding.OptionsResult options(String quoteLineItemId) {
            ConfigEngineBinding.OptionsResult r = new ConfigEngineBinding.OptionsResult();
            r.isSuccess = true;
            r.productName = 'Stub Product';
            r.hasConfigurableAttributes = true;
            r.attributesJson = '[]';
            return r;
        }
        public ConfigEngineBinding.SaveResult save(String q, String qli, String json) {
            ConfigEngineBinding.SaveResult r = new ConfigEngineBinding.SaveResult();
            r.isSuccess = true;
            r.isValid = true;
            r.savedAttributesJson = '{}';
            return r;
        }
        public ConfigEngineBinding.ReadResult read(String quoteLineItemId) {
            ConfigEngineBinding.ReadResult r = new ConfigEngineBinding.ReadResult();
            r.isSuccess = true;
            r.savedAttributesJson = '{}';
            r.configurationSummary = 'stub';
            return r;
        }
    }

    @IsTest
    static void gatewayCanBeSwappedAndRestored() {
        ConfigEngineBinding.Gateway original = ConfigEngineBinding.gateway();
        System.assertNotEquals(null, original, 'a real gateway must be installed by default');

        Test.startTest();
        ConfigEngineBinding.Gateway previous = ConfigEngineBinding.setGateway(new StubGateway());
        System.assertEquals(original, previous, 'setGateway must return the instance it displaced');
        System.assertEquals('Stub Product',
            ConfigEngineBinding.gateway().options('0QL000000000000').productName);

        ConfigEngineBinding.setGateway(previous);
        System.assertEquals(original, ConfigEngineBinding.gateway(), 'gateway must be restorable');
        Test.stopTest();
    }

    @IsTest
    static void dtosDefaultToFailureNotSuccess() {
        // Defensive: a freshly constructed DTO must never look like a success.
        System.assertEquals(false, new ConfigEngineBinding.OptionsResult().isSuccess);
        System.assertEquals(false, new ConfigEngineBinding.SaveResult().isSuccess);
        System.assertEquals(false, new ConfigEngineBinding.SaveResult().isValid);
        System.assertEquals(false, new ConfigEngineBinding.ReadResult().isSuccess);
    }
}
