/**
 * Controlling Logic extension for Action Plans V4 (SalesforceLabs/ActionPlansV4).
 *
 * Adds Controlling_Logic__c on APTemplateTask__c and APTask__c so a task can be released
 * (its standard Task created) by a logical combination of other tasks,
 * e.g. "1 OR 2", "2 AND 3", "(1 OR 2) AND 4".
 *
 * TASK NUMBERS = list position (1-based), the same number V4 shows in brackets in the
 * Controlling Task dropdown ("23 (1)" = task 1). V4 builds that list ordered by TaskIndex__c,
 * but TaskIndex__c itself is NOT the position (first task can be null, gaps after deletes),
 * so positions are always derived by ranking: TaskIndex__c ASC NULLS FIRST, CreatedDate, Id.
 *
 * A task uses EITHER Controlling Task OR Controlling Logic, never both.
 */
public with sharing class ActionPlanControllingLogicService {

    public static final String BOTH_SET_ERROR = 'Use either Controlling Task or Controlling Logic, not both.';
    public static final String CYCLE_ERROR = 'Controlling Logic creates a circular dependency between tasks. Please review the task numbers.';

    // =====================================================================
    // 1. VALIDATION - Template tasks (APTemplateTask__c)
    // =====================================================================

    /** Record-level checks (syntax, not both). No queries. */
    public static void validateTemplateTasksBefore(List<APTemplateTask__c> records) {
        for (APTemplateTask__c r : records) {
            if (String.isBlank(r.Controlling_Logic__c)) {
                continue;
            }
            r.Controlling_Logic__c = r.Controlling_Logic__c.normalizeSpace();
            if (r.TController__c != null || hasDependentIndex(r.Dependent__c)) {
                r.Controlling_Logic__c.addError(BOTH_SET_ERROR);
                continue;
            }
            String err = ActionPlanControllingLogic.validate(r.Controlling_Logic__c, null, null);
            if (err != null) {
                r.Controlling_Logic__c.addError(err);
            }
        }
    }

    /** Template-level checks: self reference, task numbers exist, no circular dependency. */
    public static void validateTemplateTasksAfter(List<APTemplateTask__c> records) {
        Set<Id> templateIds = new Set<Id>();
        for (APTemplateTask__c r : records) {
            if (r.Action_Plan_Template__c != null) {
                templateIds.add(r.Action_Plan_Template__c);
            }
        }
        if (templateIds.isEmpty()) {
            return;
        }
        Map<Id, List<Node>> nodesByGroup = new Map<Id, List<Node>>();
        for (APTemplateTask__c t : [
            SELECT Id, Action_Plan_Template__c, Controlling_Logic__c, TController__c
            FROM APTemplateTask__c
            WHERE Action_Plan_Template__c IN :templateIds
            ORDER BY Action_Plan_Template__c, TaskIndex__c ASC NULLS FIRST, CreatedDate, Id
        ]) {
            addNode(nodesByGroup, t.Action_Plan_Template__c, t.Id, t.Controlling_Logic__c, t.TController__c);
        }
        applyErrors(records, validateGroups(nodesByGroup), 'Action_Plan_Template__c');
    }

    // =====================================================================
    // 2. VALIDATION - Action Plan tasks (APTask__c)
    // =====================================================================

    public static void validatePlanTasksBefore(List<APTask__c> records) {
        for (APTask__c r : records) {
            if (String.isBlank(r.Controlling_Logic__c)) {
                continue;
            }
            r.Controlling_Logic__c = r.Controlling_Logic__c.normalizeSpace();
            if (r.Controller__c != null) {
                r.Controlling_Logic__c.addError(BOTH_SET_ERROR);
                continue;
            }
            String err = ActionPlanControllingLogic.validate(r.Controlling_Logic__c, null, null);
            if (err != null) {
                r.Controlling_Logic__c.addError(err);
            }
        }
    }

    public static void validatePlanTasksAfter(List<APTask__c> records) {
        Set<Id> planIds = new Set<Id>();
        Boolean anyLogic = false;
        for (APTask__c r : records) {
            if (r.Action_Plan__c != null) {
                planIds.add(r.Action_Plan__c);
            }
            anyLogic = anyLogic || String.isNotBlank(r.Controlling_Logic__c);
        }
        if (planIds.isEmpty() || !anyLogic) {
            return;
        }
        Map<Id, List<Node>> nodesByGroup = new Map<Id, List<Node>>();
        for (APTask__c t : [
            SELECT Id, Action_Plan__c, Controlling_Logic__c, Controller__c
            FROM APTask__c
            WHERE Action_Plan__c IN :planIds
            ORDER BY Action_Plan__c, TaskIndex__c ASC NULLS FIRST, CreatedDate, Id
        ]) {
            addNode(nodesByGroup, t.Action_Plan__c, t.Id, t.Controlling_Logic__c, t.Controller__c);
        }
        applyErrors(records, validateGroups(nodesByGroup), 'Action_Plan__c');
    }

    // =====================================================================
    // 3. COPY - legacy utility retained for compatibility/tests. The creation controller and
    // Flow invocable now copy this field before task insertion, so builder save does not
    // overwrite user edits made on the Action Plan creation screen.
    // =====================================================================

    /**
     * Legacy helper to fill Controlling_Logic__c on plan tasks from a template.
     * The current Visualforce and Flow creation routes copy the field before save; this
     * method remains available for compatibility with existing callers.
     */
    public static void applyTemplateLogic(List<APTask__c> planTasksInOrder, Id templateId) {
        if (templateId == null || planTasksInOrder == null || planTasksInOrder.isEmpty()) {
            return;
        }
        List<APTemplateTask__c> tts = [
            SELECT Subject__c, Controlling_Logic__c
            FROM APTemplateTask__c
            WHERE Action_Plan_Template__c = :templateId
            ORDER BY TaskIndex__c ASC NULLS FIRST, CreatedDate, Id
        ];
        Boolean anyLogic = false;
        for (APTemplateTask__c tt : tts) {
            anyLogic = anyLogic || String.isNotBlank(tt.Controlling_Logic__c);
        }
        if (!anyLogic) {
            return;
        }

        if (tts.size() == planTasksInOrder.size()) {
            for (Integer i = 0; i < tts.size(); i++) {
                copyIfBlank(planTasksInOrder[i], tts[i].Controlling_Logic__c);
            }
            return;
        }

        // Rows were added/removed on the plan screen: positions may have shifted, match by unique subject
        Map<String, String> logicBySubject = new Map<String, String>();
        Set<String> duplicates = new Set<String>();
        for (APTemplateTask__c tt : tts) {
            String k = tt.Subject__c == null ? '' : tt.Subject__c.toLowerCase();
            if (logicBySubject.containsKey(k)) {
                duplicates.add(k);
            }
            logicBySubject.put(k, tt.Controlling_Logic__c);
        }
        for (APTask__c apt : planTasksInOrder) {
            String k = apt.Subject__c == null ? '' : apt.Subject__c.toLowerCase();
            if (!duplicates.contains(k)) {
                copyIfBlank(apt, logicBySubject.get(k));
            }
        }
    }

    private static void copyIfBlank(APTask__c apt, String logic) {
        if (String.isNotBlank(logic) && String.isBlank(apt.Controlling_Logic__c) && (apt.Dependent__c == null || apt.Dependent__c == 'None')) {
            apt.Controlling_Logic__c = logic;
        }
    }

    // =====================================================================
    // 4. RELEASE - create the Task when the logic becomes true
    // =====================================================================

    /**
     * after insert / after update on Task. For every Action Plan whose Task was just closed,
     * evaluate the not-yet-released logic tasks in that plan and create their Tasks.
     */
    public static void releaseOnTaskClose(List<Task> newList, Map<Id, Task> oldMap) {
        Map<Id, Task> closingByApTask = new Map<Id, Task>();
        for (Task t : newList) {
            if (t.TaskAPTask__c == null || !t.IsClosed) {
                continue;
            }
            if (oldMap == null || !oldMap.get(t.Id).IsClosed) {
                closingByApTask.put(t.TaskAPTask__c, t);
            }
        }
        if (closingByApTask.isEmpty()) {
            return;
        }

        Map<Id, Task> sourceTaskByPlan = new Map<Id, Task>();
        for (APTask__c apt : [SELECT Id, Action_Plan__c FROM APTask__c WHERE Id IN :closingByApTask.keySet()]) {
            sourceTaskByPlan.put(apt.Action_Plan__c, closingByApTask.get(apt.Id));
        }
        if (sourceTaskByPlan.isEmpty()) {
            return;
        }

        List<APTask__c> allTasks = [
            SELECT Id, Action_Plan__c, Subject__c, Priority__c, Type__c, Comments__c, User__c,
                SendEmail__c, Reminder__c, Minutes_Reminder__c, DaysFromStart__c, Controlling_Logic__c,
                Task_RecordTypeId__c, Action_Plan__r.SkipWeekends__c, Action_Plan__r.SkipDay__c
            FROM APTask__c
            WHERE Action_Plan__c IN :sourceTaskByPlan.keySet()
            ORDER BY Action_Plan__c, TaskIndex__c ASC NULLS FIRST, CreatedDate, Id
        ];
        Boolean anyLogic = false;
        for (APTask__c apt : allTasks) {
            anyLogic = anyLogic || String.isNotBlank(apt.Controlling_Logic__c);
        }
        if (!anyLogic) {
            return;
        }

        Set<Id> allIds = new Map<Id, APTask__c>(allTasks).keySet();
        Set<Id> released = new Set<Id>();
        Set<Id> closed = new Set<Id>();
        for (Task t : [SELECT TaskAPTask__c, IsClosed FROM Task WHERE TaskAPTask__c IN :allIds]) {
            released.add(t.TaskAPTask__c);
            if (t.IsClosed) {
                closed.add(t.TaskAPTask__c);
            }
        }

        // Completed task numbers per plan (position = rank within the plan)
        Map<Id, Set<Integer>> completedByPlan = new Map<Id, Set<Integer>>();
        Map<Id, Integer> counter = new Map<Id, Integer>();
        for (APTask__c apt : allTasks) {
            Integer pos = (counter.containsKey(apt.Action_Plan__c) ? counter.get(apt.Action_Plan__c) : 0) + 1;
            counter.put(apt.Action_Plan__c, pos);
            if (!completedByPlan.containsKey(apt.Action_Plan__c)) {
                completedByPlan.put(apt.Action_Plan__c, new Set<Integer>());
            }
            if (closed.contains(apt.Id)) {
                completedByPlan.get(apt.Action_Plan__c).add(pos);
            }
        }

        String defaultStatus = getDefaultTaskStatus();
        Boolean taskHasRecordTypes = Schema.SObjectType.Task.fields.getMap().containsKey('recordtypeid');
        List<Task> withEmail = new List<Task>();
        List<Task> withoutEmail = new List<Task>();
        List<APTask__c> aptUpdates = new List<APTask__c>();

        for (APTask__c apt : allTasks) {
            if (String.isBlank(apt.Controlling_Logic__c) || released.contains(apt.Id)) {
                continue;
            }
            Boolean ready = false;
            try {
                ready = ActionPlanControllingLogic.evaluate(apt.Controlling_Logic__c, completedByPlan.get(apt.Action_Plan__c));
            } catch (ActionPlanControllingLogic.LogicException e) {
                ready = false; // invalid logic is blocked on save; ignore defensively
            }
            if (!ready) {
                continue;
            }

            Task source = sourceTaskByPlan.get(apt.Action_Plan__c);
            Date due = calculateDueDate(apt);

            Task t = new Task();
            t.Subject = apt.Subject__c;
            t.Priority = apt.Priority__c;
            t.Type = apt.Type__c;
            t.Description = apt.Comments__c;
            t.OwnerId = apt.User__c == null ? UserInfo.getUserId() : apt.User__c;
            t.TaskAPTask__c = apt.Id;
            t.ActivityDate = due;
            t.WhatId = source.WhatId;
            t.WhoId = source.WhoId;
            if (defaultStatus != null) {
                t.Status = defaultStatus;
            }
            if (apt.Reminder__c == true && String.isNotBlank(apt.Minutes_Reminder__c) && apt.Minutes_Reminder__c.isNumeric()) {
                t.IsReminderSet = true;
                t.ReminderDateTime = Datetime.newInstance(due.year(), due.month(), due.day(), 0, 0, 0).addMinutes(Integer.valueOf(apt.Minutes_Reminder__c));
            }
            if (taskHasRecordTypes && String.isNotBlank(apt.Task_RecordTypeId__c)) {
                t.put('RecordTypeId', apt.Task_RecordTypeId__c);
            }
            if (apt.SendEmail__c == true) {
                withEmail.add(t);
            } else {
                withoutEmail.add(t);
            }
            aptUpdates.add(new APTask__c(Id = apt.Id, ActivityDate__c = due));
        }

        if (!withEmail.isEmpty()) {
            Database.DMLOptions dmo = new Database.DMLOptions();
            dmo.EmailHeader.triggerUserEmail = true;
            Database.insert(withEmail, dmo);
        }
        if (!withoutEmail.isEmpty()) {
            Database.DMLOptions dmo = new Database.DMLOptions();
            dmo.EmailHeader.triggerUserEmail = false;
            Database.insert(withoutEmail, dmo);
        }
        if (!aptUpdates.isEmpty()) {
            update aptUpdates;
        }
    }

    // =====================================================================
    // helpers
    // =====================================================================

    /** "Days After" for a logic task = days after the date it is released (same idea as V4 dependent tasks). */
    private static Date calculateDueDate(APTask__c apt) {
        Integer days = apt.DaysFromStart__c == null ? 0 : apt.DaysFromStart__c.intValue();
        if (apt.Action_Plan__r != null && apt.Action_Plan__r.SkipWeekends__c == true && apt.Action_Plan__r.SkipDay__c != null) {
            return ActionPlansUtilities.adjustTaskDueDate(Date.today(), days, apt.Action_Plan__r.SkipDay__c);
        }
        return Date.today().addDays(days);
    }

    private static String defaultStatusCache;
    private static String getDefaultTaskStatus() {
        if (defaultStatusCache == null) {
            List<TaskStatus> ts = [SELECT ApiName FROM TaskStatus WHERE IsDefault = TRUE LIMIT 1];
            defaultStatusCache = ts.isEmpty() ? null : ts[0].ApiName;
        }
        return defaultStatusCache;
    }

    private static Boolean hasDependentIndex(String dependent) {
        return String.isNotBlank(dependent) && dependent != 'None' && dependent.isNumeric();
    }

    private class Node {
        Id recordId;
        String logic;
        Id controllerId;
    }

    /** Nodes must be added in list order - their position is their order in the group. */
    private static void addNode(Map<Id, List<Node>> nodesByGroup, Id groupId, Id recordId, String logic, Id controllerId) {
        Node n = new Node();
        n.recordId = recordId;
        n.logic = logic;
        n.controllerId = controllerId;
        if (!nodesByGroup.containsKey(groupId)) {
            nodesByGroup.put(groupId, new List<Node>());
        }
        nodesByGroup.get(groupId).add(n);
    }

    /** @return record Id -> error, plus group Id -> error for cycles */
    private static Map<Id, String> validateGroups(Map<Id, List<Node>> nodesByGroup) {
        Map<Id, String> errors = new Map<Id, String>();
        for (Id groupId : nodesByGroup.keySet()) {
            List<Node> nodes = nodesByGroup.get(groupId);
            Map<Id, Integer> posById = new Map<Id, Integer>();
            Set<Integer> positions = new Set<Integer>();
            for (Integer i = 0; i < nodes.size(); i++) {
                posById.put(nodes[i].recordId, i + 1);
                positions.add(i + 1);
            }
            Map<Integer, Set<Integer>> graph = new Map<Integer, Set<Integer>>();
            Boolean groupHasError = false;
            Boolean groupHasLogic = false;
            for (Integer i = 0; i < nodes.size(); i++) {
                Node n = nodes[i];
                Integer pos = i + 1;
                Set<Integer> deps = new Set<Integer>();
                if (n.controllerId != null && posById.containsKey(n.controllerId)) {
                    deps.add(posById.get(n.controllerId));
                }
                if (String.isNotBlank(n.logic)) {
                    groupHasLogic = true;
                    String err = ActionPlanControllingLogic.validate(n.logic, pos, positions);
                    if (err != null) {
                        errors.put(n.recordId, 'Task ' + pos + ' - ' + err);
                        groupHasError = true;
                        continue;
                    }
                    deps.addAll(ActionPlanControllingLogic.getReferencedTasks(n.logic));
                }
                graph.put(pos, deps);
            }
            if (groupHasLogic && !groupHasError && ActionPlanControllingLogic.hasCycle(graph)) {
                errors.put(groupId, CYCLE_ERROR);
            }
        }
        return errors;
    }

    private static void applyErrors(List<SObject> records, Map<Id, String> errors, String groupField) {
        if (errors.isEmpty() || records.isEmpty()) {
            return;
        }
        Set<Id> reported = new Set<Id>();
        for (SObject r : records) {
            if (errors.containsKey(r.Id)) {
                r.addError(errors.get(r.Id));
                reported.add(r.Id);
            }
            Id groupId = (Id) r.get(groupField);
            if (errors.containsKey(groupId) && !reported.contains(groupId)) {
                r.addError(errors.get(groupId));
                reported.add(groupId);
            }
        }
        // Errors on sibling rows that are not in this DML: block the save on the first record
        for (Id key : errors.keySet()) {
            if (!reported.contains(key)) {
                records[0].addError(errors.get(key));
            }
        }
    }
}
