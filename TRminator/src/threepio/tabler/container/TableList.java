/*
 * File: TableList.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import java.util.ArrayList;

/**
 * Table list is an arraylist of tables.
 * @author jhoule
 */
public class TableList extends ArrayList<XTable>
{
    /**
     * returns a table that has the value passed in row 0, col 0.
     * @param value - the value to find.
     * @see XTable#startsWith(java.lang.String) 
     * @return the table that starts with the value, null if it wasn't there.
     */
    @SuppressWarnings("empty-statement")
    public XTable getTableStarting(String value)
    {
        int i;
        for (i = 0; i < size() && !(get(i).startsWith(value)); i++);

        if (i < size())
        {
            return get(i);
        }

        return null;
    }
}
