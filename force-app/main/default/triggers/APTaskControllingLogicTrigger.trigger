/**
 * Controlling Logic extension for Action Plans V4 - Action Plan Task (APTask__c).
 * before : record-level checks (syntax, not both Controlling Task + Controlling Logic)
 * after  : plan-level checks (self reference, task numbers exist, no circular dependency)
 * Logic is copied from the template by ActionPlanCreationController (screen creation) or ActionPlanCreateInvocable (Flow creation).
 */
trigger APTaskControllingLogicTrigger on APTask__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        ActionPlanControllingLogicService.validatePlanTasksBefore(Trigger.new);
    } else {
        ActionPlanControllingLogicService.validatePlanTasksAfter(Trigger.new);
    }
}
