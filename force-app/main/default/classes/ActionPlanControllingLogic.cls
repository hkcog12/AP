/**
 * Pure (no SOQL / no DML) parser and evaluator for Action Plan "Controlling Logic".
 *
 * Grammar (AND binds tighter than OR, same as Salesforce report filter logic):
 *   expression := term   ( OR  term   )*
 *   term       := factor ( AND factor )*
 *   factor     := TASK_NUMBER | '(' expression ')'
 *
 * Accepted operators: AND, OR (case-insensitive), && and || as aliases.
 * Task numbers are 1-based and match the number shown in brackets in the
 * Controlling Task dropdown, e.g. "23 (1)" is task 1.
 *
 * Examples: "1 OR 2", "2 AND 3", "(1 OR 2) AND 4", "1 AND (2 OR 3)"
 *
 * NOT is intentionally not supported: logic must be monotonic (once true it stays
 * true as more tasks complete), otherwise a task could be released and then become
 * "un-released".
 */
public with sharing class ActionPlanControllingLogic {

    public class LogicException extends Exception {}

    private static final String T_AND = 'AND';
    private static final String T_OR = 'OR';
    private static final String T_OPEN = '(';
    private static final String T_CLOSE = ')';
    private static final Integer MAX_DIGITS = 4;

    // ------------------------------------------------------------------ public API

    /**
     * Validates the syntax and returns every task number referenced.
     * @throws LogicException with a user-friendly message when the expression is invalid
     */
    public static Set<Integer> getReferencedTasks(String expr) {
        Parser p = new Parser(tokenize(expr), null);
        p.parse();
        return p.refs;
    }

    /**
     * Evaluates the expression against the set of completed task numbers.
     * @throws LogicException when the expression is invalid
     */
    public static Boolean evaluate(String expr, Set<Integer> completedTasks) {
        Parser p = new Parser(tokenize(expr), completedTasks == null ? new Set<Integer>() : completedTasks);
        return p.parse();
    }

    /**
     * Full validation for one task.
     * @param expr            the Controlling Logic text
     * @param ownPosition     this task's number (may be null if unknown)
     * @param validPositions  all task numbers in the plan/template (null = skip existence check)
     * @return null when valid, otherwise an error message
     */
    public static String validate(String expr, Integer ownPosition, Set<Integer> validPositions) {
        if (String.isBlank(expr)) {
            return null;
        }
        Set<Integer> refs;
        try {
            refs = getReferencedTasks(expr);
        } catch (LogicException e) {
            return 'Controlling Logic "' + expr + '": ' + e.getMessage();
        }
        if (ownPosition != null && refs.contains(ownPosition)) {
            return 'Controlling Logic "' + expr + '": a task cannot depend on itself (task ' + ownPosition + ').';
        }
        if (validPositions != null) {
            List<Integer> missing = new List<Integer>();
            for (Integer r : refs) {
                if (!validPositions.contains(r)) {
                    missing.add(r);
                }
            }
            if (!missing.isEmpty()) {
                missing.sort();
                List<String> labels = new List<String>();
                for (Integer m : missing) {
                    labels.add(String.valueOf(m));
                }
                return 'Controlling Logic "' + expr + '": task number(s) ' + String.join(labels, ', ') + ' do not exist.';
            }
        }
        return null;
    }

    /**
     * Detects a circular dependency.
     * @param dependsOn task number -> task numbers it depends on (controller + logic references)
     */
    public static Boolean hasCycle(Map<Integer, Set<Integer>> dependsOn) {
        // 0 = not visited, 1 = on current path, 2 = done
        Map<Integer, Integer> state = new Map<Integer, Integer>();
        for (Integer node : dependsOn.keySet()) {
            if (visit(node, dependsOn, state)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Renumbers an expression after the task at removedPosition is deleted from the list.
     * Numbers above removedPosition are shifted down by 1.
     * @return the renumbered expression, or null if the expression referenced the removed task
     *         (caller should clear it and tell the user)
     */
    public static String renumberAfterRemoval(String expr, Integer removedPosition) {
        if (String.isBlank(expr)) {
            return expr;
        }
        List<String> tokens;
        try {
            tokens = tokenize(expr);
        } catch (LogicException e) {
            return expr; // leave invalid text untouched; validation will report it
        }
        List<String> out = new List<String>();
        for (String tok : tokens) {
            if (tok.isNumeric()) {
                Integer n = Integer.valueOf(tok);
                if (n == removedPosition) {
                    return null;
                }
                out.add(String.valueOf(n > removedPosition ? n - 1 : n));
            } else {
                out.add(tok);
            }
        }
        return String.join(out, ' ').replace('( ', '(').replace(' )', ')');
    }

    // ------------------------------------------------------------------ internals

    private static Boolean visit(Integer node, Map<Integer, Set<Integer>> graph, Map<Integer, Integer> state) {
        Integer s = state.get(node);
        if (s == 1) {
            return true;
        }
        if (s == 2) {
            return false;
        }
        state.put(node, 1);
        Set<Integer> next = graph.get(node);
        if (next != null) {
            for (Integer n : next) {
                if (visit(n, graph, state)) {
                    return true;
                }
            }
        }
        state.put(node, 2);
        return false;
    }

    @TestVisible
    private static List<String> tokenize(String expr) {
        if (String.isBlank(expr)) {
            throw new LogicException('Expression is empty.');
        }
        String s = expr.toUpperCase().replace('&&', ' AND ').replace('||', ' OR ');
        List<String> tokens = new List<String>();
        Integer i = 0;
        Integer n = s.length();
        while (i < n) {
            String c = s.substring(i, i + 1);
            if (String.isBlank(c)) {
                i++;
            } else if (c == T_OPEN || c == T_CLOSE) {
                tokens.add(c);
                i++;
            } else if (c.isNumeric()) {
                Integer j = i;
                while (j < n && s.substring(j, j + 1).isNumeric()) {
                    j++;
                }
                String num = s.substring(i, j);
                if (num.length() > MAX_DIGITS) {
                    throw new LogicException('Task number "' + num + '" is too large.');
                }
                tokens.add(num);
                i = j;
            } else if (c.isAlpha()) {
                Integer j = i;
                while (j < n && s.substring(j, j + 1).isAlpha()) {
                    j++;
                }
                String word = s.substring(i, j);
                if (word != T_AND && word != T_OR) {
                    throw new LogicException('Unknown word "' + word + '". Use AND, OR and brackets only.');
                }
                tokens.add(word);
                i = j;
            } else {
                throw new LogicException('Invalid character "' + c + '". Use task numbers, AND, OR and brackets only.');
            }
        }
        return tokens;
    }

    /** Recursive-descent parser. Evaluates both sides of every operator so that syntax and references are always fully checked. */
    private class Parser {
        private List<String> tokens;
        private Integer pos = 0;
        private Set<Integer> completed; // null = validate only
        public Set<Integer> refs = new Set<Integer>();

        Parser(List<String> tokens, Set<Integer> completed) {
            this.tokens = tokens;
            this.completed = completed;
        }

        Boolean parse() {
            Boolean v = parseOr();
            if (pos < tokens.size()) {
                throw new LogicException('Unexpected "' + tokens[pos] + '" at position ' + (pos + 1) + '.');
            }
            return v;
        }

        private String peek() {
            return pos < tokens.size() ? tokens[pos] : null;
        }

        private String next() {
            return pos < tokens.size() ? tokens[pos++] : null;
        }

        private Boolean parseOr() {
            Boolean v = parseAnd();
            while (peek() == T_OR) {
                pos++;
                Boolean right = parseAnd();
                v = v || right;
            }
            return v;
        }

        private Boolean parseAnd() {
            Boolean v = parseFactor();
            while (peek() == T_AND) {
                pos++;
                Boolean right = parseFactor();
                v = v && right;
            }
            return v;
        }

        private Boolean parseFactor() {
            String tok = next();
            if (tok == null) {
                throw new LogicException('Expression ends unexpectedly.');
            }
            if (tok == T_OPEN) {
                Boolean v = parseOr();
                if (next() != T_CLOSE) {
                    throw new LogicException('Missing closing bracket.');
                }
                return v;
            }
            if (tok.isNumeric()) {
                Integer num = Integer.valueOf(tok);
                if (num < 1) {
                    throw new LogicException('Task numbers start at 1.');
                }
                refs.add(num);
                return completed != null && completed.contains(num);
            }
            throw new LogicException('Expected a task number or "(" but found "' + tok + '".');
        }
    }
}
