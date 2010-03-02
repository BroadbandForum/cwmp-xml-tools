/*
 * File: TableReorderer.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import java.util.HashMap;
import java.util.Iterator;
import java.util.Map.Entry;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.Table;

/**
 * Table Reorderer orders Tables based on information on where they should be.
 * @author jhoule
 */
public class TableReorderer
{

    /**
     * re-orders a Model Table based on a HashMap of item names.
     * the keys are items that are to be moved.
     * the values are the items that they should follow.
     * @param table - the Table to re-order.
     * @param paired - the map of changes to make to the table.
     * @return the Table, re-ordered.
     */
    public static ModelTable reOrder(ModelTable table, HashMap<String, String> paired)
    {

        Iterator<Entry<String, String>> it;
        ModelTable copied;
        String name, other;
        Entry<String, String> ent;

        if (!paired.isEmpty())
        {
            it = paired.entrySet().iterator();
            copied = new ModelTable(table);

            while (it.hasNext())
            {
                ent = it.next();
                name = ent.getKey();
                other = ent.getValue();

                if (name.contains("DeviceInfo") || other.contains("DeviceInfo"))
                {
                    System.err.println(copied.toString());
                }
                tableMoveByKey(copied, name, other);
            }

            return copied;
        }
        return table;
    }

    /**
     * moves items in a table based on the key of the items. The item named <code>name</code> is placed
     * based on the item named <code>other</code>
     * @param table - the table to do the move in.
     * @param name - the name of the item to be moving.
     * @param other - the name of the item to do the move based around.
     * @throws IllegalStateException - when either the item to move or the item to base movement on are not in the table.
     */
    private static void tableMoveByKey(Table table, String name, String other) throws IllegalStateException
    {
        int oldIndex, otherIndex;

        oldIndex = table.indexByKeyOf(name);


        otherIndex = table.indexOfClosestMatch(other, name);

        if (oldIndex == -1)
        {
            throw new IllegalStateException("the item named " + name + " is missing from the table " + table.getVersion());
        }

        if (otherIndex == -1)
        {
            throw new IllegalStateException("the item named " + other + " is missing from the table " + table.getVersion());
        }

        // item should be right after dmr item
        otherIndex++;

        table.move(oldIndex, otherIndex);

    }
}
