/*
Action Plans v4
David Schach 2022
https://appexchange.salesforce.com/appxListingDetail?listingId=a0N4V00000Gg6NVUAZ

Action Plans v3
Force.com Labs 2011
http://appexchange.salesforce.com/listingDetail?listingId=a0N30000003HcINEA0

Copyright (c) 2022, salesforce.com, inc.
All rights reserved.
SPDX-License-Identifier: BSD-3-Clause
For full license text, see the LICENSE file in the repo root or https://opensource.org/licenses/BSD-3-Clause
*/
/**
 * Test class for Invocable Apex class
 *
 * @author {@link [David Schach](https://github.com/dschach)}
 * @since 2022
 * @since 2023 System.assert to Assert class + error messages
 * @see ActionPlanCreateInvocable
 * @group Tests
 */
@IsTest
private class ActionPlanCreateInvocableTest {
	private static final Integer TASK_COUNT = 7;
	private static final Integer BULK_COUNT = 100;

	@IsTest
	private static void relatedAccount() {
		Action_Plans_Settings__c aps = Action_Plans_Settings__c.getOrgDefaults();
		aps.Chatter_Object_Brag__c = true;
		aps.Unassigned_Task_Assigned_to_Owner__c = true;
		try {
			upsert aps;
		} catch (Exception e) {
			update aps;
		}

		Account a = new Account();
		a.Name = 'TestAcct';
		insert a;

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);
		List<APTemplateTask__c> allTaskTemplates = [SELECT Id, Dependent__c, SendEmail__c, Reminder__c FROM APTemplateTask__c];
		for (APTemplateTask__c at : allTaskTemplates) {
			at.SendEmail__c = true;
			at.Reminder__c = true;
			at.Dependent__c = null;
			at.User__c = null;
		}
		update allTaskTemplates;

		Test.startTest();

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 1, apTemplate.Name + 'TEST');

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void copiesControllingLogicAndReleasesOnlyWhenReady() {
		Account account = new Account(Name = 'Controlling Logic Invocable Test');
		insert account;
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlanTemplate__c template = testUtil.createNewActionPlanTemplate(3);
		List<APTemplateTask__c> templateTasks = [
			SELECT Id, Controlling_Logic__c
			FROM APTemplateTask__c
			WHERE Action_Plan_Template__c = :template.Id
			ORDER BY TaskIndex__c ASC
		];
		templateTasks[2].Controlling_Logic__c = '1 OR 2';
		update templateTasks[2];

		ActionPlanCreateInvocable.CreateActionPlanRequest request = setupRequest(template.Id, account.Id, 0);
		Test.startTest();
		List<Id> createdPlanIds = ActionPlanCreateInvocable.makeActionPlanFromTemplate(new List<ActionPlanCreateInvocable.CreateActionPlanRequest>{ request });
		Test.stopTest();

		Assert.areEqual(1, createdPlanIds.size(), 'One Action Plan should be created.');
		List<APTask__c> planTasks = [
			SELECT Controlling_Logic__c
			FROM APTask__c
			WHERE Action_Plan__c = :createdPlanIds[0]
			ORDER BY TaskIndex__c ASC
		];
		Assert.areEqual('1 OR 2', planTasks[2].Controlling_Logic__c, 'Invocable creation should copy template Controlling Logic.');
		Assert.areEqual(2, [SELECT COUNT() FROM Task WHERE TaskAPTask__r.Action_Plan__c = :createdPlanIds[0]], 'A logic-controlled task must not be created before its expression is satisfied.');
	}

	@IsTest
	private static void relatedContact() {
		Action_Plans_Settings__c aps = Action_Plans_Settings__c.getOrgDefaults();
		aps.Chatter_Object_Brag__c = false;
		aps.Unassigned_Task_Assigned_to_Owner__c = false;
		try {
			upsert aps;
		} catch (Exception e) {
			update aps;
		}

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Contact c = testUtil.createNewContact();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);
		apTemplate.SkipDay__c = 'End of previous week';
		update apTemplate;

		List<APTemplateTask__c> allTaskTemplates = [SELECT Id, Dependent__c, SendEmail__c, Reminder__c FROM APTemplateTask__c];
		for (APTemplateTask__c at : allTaskTemplates) {
			at.SendEmail__c = true;
			at.Reminder__c = true;
			at.Dependent__c = null;
			at.User__c = UserInfo.getUserId();
		}
		update allTaskTemplates;

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, c.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void relatedLead() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Lead a = testUtil.createNewLead();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);
		apTemplate.SkipDay__c = null;
		apTemplate.SkipWeekends__c = false;
		update apTemplate;

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void relatedOpportunity() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Opportunity a = testUtil.createNewOpportunity();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void relatedCampaign() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Campaign a = testUtil.createNewCampaign();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void relatedCase() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Case a = testUtil.createNewCase();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void relatedContract() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		Contract a = testUtil.createNewContract();

		Test.startTest();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, 0);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
	}

	@IsTest
	private static void bulkAccounts() {
		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();
		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(2);
		apTemplate.name = 'B';
		update apTemplate;

		List<Account> toInsert = new List<Account>();

		for (Integer i = 0; i < BULK_COUNT; i++) {
			toInsert.add(testUtil.createNewAccount(false));
		}
		for (Account a : toInsert) {
			a.Type = null;
		}
		insert toInsert;

		Test.startTest();

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();

		for (Account a : toInsert) {
			ActionPlanCreateInvocable.CreateActionPlanRequest req = new ActionPlanCreateInvocable.CreateActionPlanRequest();
			req.templateNameOrID = apTemplate.Id;
			req.relatedRecordID = a.Id;
			req.daysToActionPlanStart = 0;
			requests.add(req);
		}
		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);
		Test.stopTest();
		Assert.areEqual(BULK_COUNT, resultIDs.size(), 'Should have made one AP per wrapper');
		Assert.areEqual(BULK_COUNT, [SELECT COUNT() FROM ActionPlan__c WHERE Account__c != NULL], 'Failed to create enough Account-linked APs');
	}

	@IsTest
	private static void checkWeekendDueDate() {
		Weekend_Day__mdt weekend = [
			SELECT Id, Days_from_end_of_previous_week__c, Days_to_start_of_next_week__c, DeveloperName
			FROM Weekend_Day__mdt
			WHERE Days_to_start_of_next_week__c != 0
		][0];
		String weekendDayName = weekend.DeveloperName;
		Date upcomingWeekendDay = Date.today();
		Integer daysToWeekendDay = 0;

		for (daysToWeekendDay = 0; daysToWeekendDay < 8; daysToWeekendDay++) {
			upcomingWeekendDay = Date.today().addDays(daysToWeekendDay);
			if (ActionPlansUtilities.getDayOfWeek(upcomingWeekendDay) == weekendDayName) {
				break;
			}
		}

		Action_Plans_Settings__c aps = Action_Plans_Settings__c.getOrgDefaults();
		aps.Chatter_Object_Brag__c = false;
		aps.Unassigned_Task_Assigned_to_Owner__c = true;
		try {
			upsert aps;
		} catch (Exception e) {
			update aps;
		}

		Account a = new Account();
		a.Name = 'TestAcct';
		insert a;

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);

		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM APTemplateTask__c], 'Failed to create the correct number of APTemplate Tasks');

		apTemplate.SkipDay__c = 'Start of next week';
		update apTemplate;

		List<APTemplateTask__c> allTaskTemplates = [SELECT Id, Dependent__c, SendEmail__c, Reminder__c FROM APTemplateTask__c];
		for (APTemplateTask__c at : allTaskTemplates) {
			at.SendEmail__c = false;
			at.Reminder__c = false;
			at.Dependent__c = null;
			at.User__c = null;
		}
		update allTaskTemplates;

		Test.startTest();

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest(apTemplate.Id, a.Id, daysToWeekendDay);

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Failed to create task IDs in the invocable class');
		Assert.areEqual(1, resultIDs.size(), 'Should only have created one Id');
		Assert.areEqual(TASK_COUNT, [SELECT COUNT() FROM Task], 'Did not create the desired number of tasks');
		/* for (Task t : [SELECT Id, ActivityDate FROM Task]) {
			System.debug('Task is due on ' + t.ActivityDate + ' which is a ' + ActionPlansUtilities.getDayOfWeek(t.ActivityDate));
		} */
		Assert.areEqual(0, [SELECT COUNT() FROM Task WHERE ActivityDate = :upcomingWeekendDay], 'Task should not have been scheduled for a weekend');
	}

	@IsTest
	private static void bogusTemplateName() {
		Action_Plans_Settings__c aps = Action_Plans_Settings__c.getOrgDefaults();
		aps.Chatter_Object_Brag__c = true;
		aps.Unassigned_Task_Assigned_to_Owner__c = true;
		try {
			upsert aps;
		} catch (Exception e) {
			update aps;
		}

		Account a = new Account();
		a.Name = 'TestAcct';
		insert a;

		ActionPlansTestUtilities testUtil = new ActionPlansTestUtilities();

		ActionPlanTemplate__c apTemplate = testUtil.createNewActionPlanTemplate(TASK_COUNT);
		List<APTemplateTask__c> allTaskTemplates = [SELECT Id, Dependent__c, SendEmail__c, Reminder__c FROM APTemplateTask__c];
		for (APTemplateTask__c at : allTaskTemplates) {
			at.SendEmail__c = true;
			at.Reminder__c = true;
			at.Dependent__c = null;
			at.User__c = null;
		}
		update allTaskTemplates;

		Test.startTest();

		ActionPlanCreateInvocable.CreateActionPlanRequest req = setupRequest('Fake Name', a.Id, 1, apTemplate.Name + 'TEST');

		List<ActionPlanCreateInvocable.CreateActionPlanRequest> requests = new List<ActionPlanCreateInvocable.CreateActionPlanRequest>();
		requests.add(req);

		List<Id> resultIDs = ActionPlanCreateInvocable.makeActionPlanFromTemplate(requests);

		Test.stopTest();
		Assert.areNotEqual(null, resultIDs, 'Returned List should not be null');
		Assert.isTrue(resultIDs.isEmpty(), 'Returned List should be empty');
		Assert.areEqual(0, [SELECT COUNT() FROM Task], 'No Tasks should have been created');
	}

	/**
	 * Helper method for setting up a request for Invocable Apex
	 *
	 * @param templateId            Name or Id of Action Plan Template
	 * @param relatedID             Parent record Id
	 * @param daysToActionPlanStart Days after today to start the first task
	 * @return                      `ActionPlanCreateInvocable.CreateActionPlanRequest` Used in Invocable Apex
	 * @see ActionPlanCreateInvocableTest.setupRequest[1]
	 */
	private static ActionPlanCreateInvocable.CreateActionPlanRequest setupRequest(String templateId, Id relatedID, Integer daysToActionPlanStart) {
		ActionPlanCreateInvocable.CreateActionPlanRequest req = new ActionPlanCreateInvocable.CreateActionPlanRequest();
		req.templateNameOrID = templateId;
		req.relatedRecordID = relatedId;
		req.daysToActionPlanStart = daysToActionPlanStart;
		return req;
	}

	/**
	 * Helper method for setting up a request for Invocable Apex
	 *
	 * @param templateId            Name or Id of Action Plan Template
	 * @param relatedID             Parent record Id
	 * @param daysToActionPlanStart Days after today to start the first task
	 * @param actionPlanName        Intended name of the Action Plan
	 * @return                      `ActionPlanCreateInvocable.CreateActionPlanRequest` Used in Invocable Apex
	 * @see ActionPlanCreateInvocableTest.setupRequest[0]
	 */
	private static ActionPlanCreateInvocable.CreateActionPlanRequest setupRequest(String templateId, Id relatedID, Integer daysToActionPlanStart, String actionPlanName) {
		ActionPlanCreateInvocable.CreateActionPlanRequest req = new ActionPlanCreateInvocable.CreateActionPlanRequest();
		req.templateNameOrID = templateId;
		req.relatedRecordID = relatedId;
		req.daysToActionPlanStart = daysToActionPlanStart;
		req.actionPlanName = actionPlanName;
		return req;
	}
}