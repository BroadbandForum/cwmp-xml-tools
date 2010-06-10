/*
 * File: NamedStringLists.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.container;

import java.util.ListIterator;

/**
 * A NamedStringLists has String keys and LinkedList Values.
 *
 * @author jhoule
 */
public class NamedStringLists extends NamedLists<String>
{
    /**
     * creates and returns a string containing all values associated with type t
     * returns empty string if no info for that type.
     * @param t - the type to get values for.
     * @return values or empty string.
     */
    public String getValsAsString(String t)
    {

        ListIterator<String> itVals;
        StringBuffer buff = new StringBuffer();

        if (this.containsKey(t))
        {
            itVals = this.get(t).listIterator();

            while (itVals.hasNext())
            {
                buff.append(itVals.next());
            }
        }
        return buff.toString();
    }
}
