/**
 * Integration tests for the Controlling Logic extension.
 * Creates Action Plan records directly. If your org adds extra required fields /
 * validation rules on ActionPlan__c, APTask__c or APTemplateTask__c, add them in the factory methods below.
 */
@IsTest
private class ActionPlanControllingLogicServiceTest {

    private static String closedStatus() {
        return [SELECT ApiName FROM TaskStatus WHERE IsClosed = TRUE LIMIT 1].ApiName;
    }

    private static ActionPlan__c newPlan(Id accountId, Id templateId) {
        ActionPlan__c ap = new ActionPlan__c(
            Name = 'Logic Plan',
            Account__c = accountId,
            StartDate__c = Date.today(),
            SkipWeekends__c = false,
            Action_Plan_Template__c = templateId
        );
        insert ap;
        return ap;
    }

    private static APTask__c newApTask(Id planId, Integer idx, String logic) {
        return new APTask__c(
            Action_Plan__c = planId,
            Subject__c = 'Task ' + (idx + 1),
            TaskIndex__c = idx,
            DaysFromStart__c = 1,
            Dependent__c = 'None',
            Priority__c = 'Normal',
            User__c = UserInfo.getUserId(),
            Controlling_Logic__c = logic
        );
    }

    private static Task newTask(APTask__c apt, Id whatId) {
        return new Task(Subject = apt.Subject__c, TaskAPTask__c = apt.Id, WhatId = whatId, OwnerId = UserInfo.getUserId());
    }

    private static Integer taskCount(Id aptId) {
        return [SELECT COUNT() FROM Task WHERE TaskAPTask__c = :aptId];
    }

    /**
     * Task 3 = "1 OR 2", Task 4 = "2 AND 3"
     */
    @IsTest
    static void releasesTasksWhenLogicBecomesTrue() {
        Account acc = new Account(Name = 'Logic Test');
        insert acc;
        ActionPlan__c ap = newPlan(acc.Id, null);

        List<APTask__c> apts = new List<APTask__c>{
            newApTask(ap.Id, 0, null),
            newApTask(ap.Id, 1, null),
            newApTask(ap.Id, 2, '1 OR 2'),
            newApTask(ap.Id, 3, '2 AND 3')
        };
        insert apts;

        // Simulate the builder: only tasks 1 and 2 get a Task
        Task t1 = newTask(apts[0], acc.Id);
        Task t2 = newTask(apts[1], acc.Id);
        insert new List<Task>{ t1, t2 };

        String doneStatus = closedStatus();
        Test.startTest();

        // Complete task 1 -> task 3 released ("1 OR 2"), task 4 not ("2 AND 3")
        t1.Status = doneStatus;
        update t1;
        System.assertEquals(1, taskCount(apts[2].Id), 'Task 3 should be created after task 1');
        System.assertEquals(0, taskCount(apts[3].Id), 'Task 4 must wait for 2 AND 3');

        // Complete task 2 -> task 3 must NOT be duplicated, task 4 still waits for 3
        t2.Status = doneStatus;
        update t2;
        System.assertEquals(1, taskCount(apts[2].Id), 'Task 3 must not be created twice');
        System.assertEquals(0, taskCount(apts[3].Id));

        // Complete task 3 -> task 4 released
        Task t3 = [SELECT Id, WhatId FROM Task WHERE TaskAPTask__c = :apts[2].Id LIMIT 1];
        System.assertEquals(acc.Id, t3.WhatId, 'Released task keeps the same related record');
        t3.Status = doneStatus;
        update t3;
        System.assertEquals(1, taskCount(apts[3].Id), 'Task 4 should be created after 2 AND 3');

        Test.stopTest();
    }

    @IsTest
    static void rejectsInvalidLogic() {
        Account acc = new Account(Name = 'Logic Test');
        insert acc;
        ActionPlan__c ap = newPlan(acc.Id, null);
        insert new List<APTask__c>{ newApTask(ap.Id, 0, null), newApTask(ap.Id, 1, null) };

        List<String> badLogic = new List<String>{ '1 OR', '1 OR 9', '3' }; // syntax, missing task, self reference
        for (String logic : badLogic) {
            Boolean failed = false;
            try {
                insert newApTask(ap.Id, 2, logic);
            } catch (DmlException e) {
                failed = true;
            }
            System.assert(failed, 'Expected validation error for: ' + logic);
        }
    }

    @IsTest
    static void rejectsControllerAndLogicTogether() {
        Account acc = new Account(Name = 'Logic Test');
        insert acc;
        ActionPlan__c ap = newPlan(acc.Id, null);
        APTask__c first = newApTask(ap.Id, 0, null);
        insert first;
        APTask__c second = newApTask(ap.Id, 1, '1');
        second.Controller__c = first.Id;
        Boolean failed = false;
        try {
            insert second;
        } catch (DmlException e) {
            failed = true;
        }
        System.assert(failed, 'Controller + logic together must be rejected');
    }

    @IsTest
    static void copiesLogicFromTemplate() {
        ActionPlanTemplate__c tmpl = new ActionPlanTemplate__c(Name = 'Logic Template');
        insert tmpl;
        List<APTemplateTask__c> tts = new List<APTemplateTask__c>();
        for (Integer i = 0; i < 3; i++) {
            tts.add(new APTemplateTask__c(
                Action_Plan_Template__c = tmpl.Id,
                Subject__c = 'Template Task ' + (i + 1),
                TaskIndex__c = (i == 0 ? null : i), // V4: first row has no TaskIndex
                DaysFromStart__c = 1,
                Dependent__c = 'None',
                Priority__c = 'Normal',
                Controlling_Logic__c = (i == 2 ? '1 OR 2' : null)
            ));
        }
        insert tts;

        // Same number of rows -> by position
        List<APTask__c> plan = new List<APTask__c>{
            new APTask__c(Subject__c = 'A'), new APTask__c(Subject__c = 'B'), new APTask__c(Subject__c = 'C')
        };
        ActionPlanControllingLogicService.applyTemplateLogic(plan, tmpl.Id);
        System.assertEquals('1 OR 2', plan[2].Controlling_Logic__c);
        System.assertEquals(null, plan[0].Controlling_Logic__c);

        // Different number of rows -> by subject
        List<APTask__c> plan2 = new List<APTask__c>{ new APTask__c(Subject__c = 'Template Task 3'), new APTask__c(Subject__c = 'X') };
        ActionPlanControllingLogicService.applyTemplateLogic(plan2, tmpl.Id);
        System.assertEquals('1 OR 2', plan2[0].Controlling_Logic__c);
    }

    @IsTest
    static void rejectsCircularTemplateLogic() {
        ActionPlanTemplate__c tmpl = new ActionPlanTemplate__c(Name = 'Cycle Template');
        insert tmpl;
        List<APTemplateTask__c> tts = new List<APTemplateTask__c>{
            new APTemplateTask__c(Action_Plan_Template__c = tmpl.Id, Subject__c = 'A', TaskIndex__c = 0, DaysFromStart__c = 1, Dependent__c = 'None', Priority__c = 'Normal', Controlling_Logic__c = '2'),
            new APTemplateTask__c(Action_Plan_Template__c = tmpl.Id, Subject__c = 'B', TaskIndex__c = 1, DaysFromStart__c = 1, Dependent__c = 'None', Priority__c = 'Normal', Controlling_Logic__c = '1')
        };
        Boolean failed = false;
        try {
            insert tts;
        } catch (DmlException e) {
            failed = true;
        }
        System.assert(failed, 'Circular logic must be rejected');
    }
}
