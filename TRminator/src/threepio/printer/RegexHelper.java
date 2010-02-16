/*
 * File: RegexHelper.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.printer;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * RegexHelper has methods that expand upon the default Regular Expressions functionality in Java.
 * Essnetially, RegExHelper adds methods to the Matcher class, which cannot be extended.
 * @author jhoule
 */
public class RegexHelper{

    /**
     * extracts all substrings of the main string that match the pattern.
     * @param regex - the pattern the substrings are to match.
     * @param body - the string to gather the substrings from.
     * @return a list of all matching substrings of the main string
     */
    public static ArrayList<String> extractAll (String regex, String body)
    {
        ArrayList list = new ArrayList<String>();
        Pattern pat = Pattern.compile(regex);
        Matcher matcher = pat.matcher(body);

        while (matcher.find())
        {
            list.add(matcher.group());
        }

        return list;
    }

    /**
     * extracts all substrings of the main string that match according to m.
     * @param m - the matcher the substrings are to match.
     * @param body - the string to gather the substrings from.
     * @return a list of all matching substrings of the main string
     */
    public static ArrayList<String> extractAll (Matcher m, String body)
    {
         ArrayList list = new ArrayList<String>();

         m.reset();
        while (m.find())
        {
            list.add(m.group());
        }

        return list;
    }

    /**
     * Changeall changes all instances that match to the replacement text (place holder).
     * It compiles a list of the snippets it removed, in order.
     * @param m - a matcher to match the snippets against.
     * @param body - the string to change.
     * @param replacement - the string to put in place.
     * @param list - the list to dump matching snippets into.
     * @return the list of snippets replaced. Side effect is new string placed in result.
     */
    public static String changeAll (Matcher m, String body, String replacement, List<String> list)
    {
        String tag;

         m.reset();

        while (m.find())
        {
            tag = m.group();
            list.add(tag);
            body = body.replace(tag, replacement);
        }

        return body;
    }

}
