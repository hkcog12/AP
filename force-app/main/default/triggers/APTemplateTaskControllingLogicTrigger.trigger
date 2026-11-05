/**
 * Controlling Logic extension for Action Plans V4 - Action Plan Template Task (APTemplateTask__c).
 */
trigger APTemplateTaskControllingLogicTrigger on APTemplateTask__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        ActionPlanControllingLogicService.validateTemplateTasksBefore(Trigger.new);
    } else {
        ActionPlanControllingLogicService.validateTemplateTasksAfter(Trigger.new);
    }
}
