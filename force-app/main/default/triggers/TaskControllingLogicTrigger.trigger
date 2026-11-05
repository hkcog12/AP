/**
 * Controlling Logic extension for Action Plans V4 - standard Task.
 * When an Action Plan Task's Task is closed, release (create) every task in the same
 * plan whose Controlling_Logic__c has now become true.
 */
trigger TaskControllingLogicTrigger on Task (after insert, after update) {
    ActionPlanControllingLogicService.releaseOnTaskClose(Trigger.new, Trigger.isUpdate ? Trigger.oldMap : null);
}
