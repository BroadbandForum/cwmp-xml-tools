/*
 * File: StringMultiMap.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.printer.container;

import java.util.ListIterator;

/**
 * A StringMultiMap has String keys and LinkedList<String> Values.
 *
 * @author jhoule
 */
public class StringMultiMap extends MultiMap<String>
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

        if (this.contains(t))
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
