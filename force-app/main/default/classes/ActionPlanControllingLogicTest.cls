/**
 * Unit tests for the pure parser/evaluator. No org data required.
 */
@IsTest
private class ActionPlanControllingLogicTest {

    @IsTest
    static void orLogic() {
        System.assertEquals(false, ActionPlanControllingLogic.evaluate('1 OR 2', new Set<Integer>()));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('1 OR 2', new Set<Integer>{ 1 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('1 or 2', new Set<Integer>{ 2 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('1 || 2', new Set<Integer>{ 2 }));
    }

    @IsTest
    static void andLogic() {
        System.assertEquals(false, ActionPlanControllingLogic.evaluate('2 AND 3', new Set<Integer>{ 2 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('2 AND 3', new Set<Integer>{ 2, 3 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('2 && 3', new Set<Integer>{ 2, 3 }));
    }

    @IsTest
    static void bracketsAndPrecedence() {
        // AND binds tighter: 1 OR (2 AND 3)
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('1 OR 2 AND 3', new Set<Integer>{ 1 }));
        System.assertEquals(false, ActionPlanControllingLogic.evaluate('(1 OR 2) AND 3', new Set<Integer>{ 1 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('(1 OR 2) AND 3', new Set<Integer>{ 2, 3 }));
        System.assertEquals(true, ActionPlanControllingLogic.evaluate('((1)) AND (2 OR (3 AND 4))', new Set<Integer>{ 1, 3, 4 }));
        System.assertEquals(false, ActionPlanControllingLogic.evaluate('1', null));
    }

    @IsTest
    static void referencedTasks() {
        Set<Integer> refs = ActionPlanControllingLogic.getReferencedTasks('(1 OR 2) AND 4');
        System.assertEquals(new Set<Integer>{ 1, 2, 4 }, refs);
    }

    @IsTest
    static void syntaxErrors() {
        List<String> bad = new List<String>{ '', '1 OR', 'OR 1', '(1 OR 2', '1 2', '1 XOR 2', '1 + 2', '0', ')', '99999', '1 AND ()' };
        for (String expr : bad) {
            Boolean failed = false;
            try {
                ActionPlanControllingLogic.getReferencedTasks(expr);
            } catch (ActionPlanControllingLogic.LogicException e) {
                failed = true;
            }
            System.assert(failed, 'Expected failure for: ' + expr);
        }
    }

    @IsTest
    static void validateMessages() {
        System.assertEquals(null, ActionPlanControllingLogic.validate('1 OR 2', 3, new Set<Integer>{ 1, 2, 3 }));
        System.assertEquals(null, ActionPlanControllingLogic.validate(null, 3, null));
        System.assert(ActionPlanControllingLogic.validate('1 OR 3', 3, null).contains('itself'));
        System.assert(ActionPlanControllingLogic.validate('1 OR 7', 3, new Set<Integer>{ 1, 2, 3 }).contains('7'));
        System.assert(ActionPlanControllingLogic.validate('1 OR', 3, null) != null);
    }

    @IsTest
    static void cycles() {
        Map<Integer, Set<Integer>> ok = new Map<Integer, Set<Integer>>{
            1 => new Set<Integer>(),
            2 => new Set<Integer>{ 1 },
            3 => new Set<Integer>{ 1, 2 },
            4 => new Set<Integer>{ 2, 3 }
        };
        System.assertEquals(false, ActionPlanControllingLogic.hasCycle(ok));

        Map<Integer, Set<Integer>> loop123 = new Map<Integer, Set<Integer>>{
            1 => new Set<Integer>{ 3 },
            2 => new Set<Integer>{ 1 },
            3 => new Set<Integer>{ 2 }
        };
        System.assertEquals(true, ActionPlanControllingLogic.hasCycle(loop123));
    }

    @IsTest
    static void renumberAfterRemoval() {
        System.assertEquals('(1 OR 2) AND 3', ActionPlanControllingLogic.renumberAfterRemoval('(1 OR 3) AND 4', 2));
        System.assertEquals(null, ActionPlanControllingLogic.renumberAfterRemoval('1 OR 2', 2));
        System.assertEquals('1 OR', ActionPlanControllingLogic.renumberAfterRemoval('1 OR', 3));
        System.assertEquals(null, ActionPlanControllingLogic.renumberAfterRemoval(null, 1));
    }
}
