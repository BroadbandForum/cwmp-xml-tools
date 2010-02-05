/*
 * File: Table.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import threepio.container.Versioned;
import threepio.tabler.Path;

/**
 * Table containsInCell some shared functionality for tables.
 * @author jhoule
 */
public abstract class Table extends IndexedHashMap<String, Row> implements Versioned
{

    /**
     * the version of the table.
     */
    String version;
    /**
     * The character that separates the parts of a path for an object.
     */

    /**
     * a map where the keys are names of items and the values are other items that are their "DMR previous" property.
     */
    private HashMap<String, String> dmrInfoMap;

    /**
     * The string that is the delimiter in a Path for an object or param.
     */
    public static String DELIM = Path.delim;

            /**
     * The string to insert into a cell that is blank.
     * This is currently the HTML non-breaking space.
     */
    public static String BLANK_CELL_TEXT = "&nbsp";

    /**
     * no-argument constructor
     * sets the version to null.
     */
    public Table()
    {
        version = null;
        dmrInfoMap = new HashMap<String, String>();
    }

    /**
     * copy constructor.
     * @param t - the other table.
     */
    public Table(Table t)
    {
        this();
        this.addAll(t);

        this.version = t.version;
        this.dmrInfoMap.putAll(t.dmrInfoMap);
    }

    @Override
    public String getVersion()
    {
        return version;
    }

    @Override
    public void setVersion(String v)
    {
        version = new String(v);
    }

    /**
     * returns the mapped DMR info for rows that have it.
     * @return the map of DMR info.
     */
    public HashMap<String, String> getDMRs()
    {
        return dmrInfoMap;
    }

    /**
     * adds a DMR entry to the DMR Map
     * @param row - the name of the row
     * @param dmr - the name of the item in its dmr statement.
     */
    public void addDmr(String row, String dmr)
    {
        if (! row.equals(dmr))
        {
            dmrInfoMap.put(row, dmr);
        }
    }

    /**
     * adds another table's contents to this one.
     * @param table - the other table.
     */
    public void put(Table table)
    {

        for (int i = 0; i < table.size(); i++)
        {
            this.put(table.get(i));
        }
    }

    /**
     * make every row in this table have stale cells.
     * they won't have any diffing info.
     */
    public void makeStale()
    {
        for (int i = 0; i < this.size(); i++)
        {
            this.get(i).getValue().makeStale();
        }
    }

    /**
     * returns if something in the table is changed.
     * @return true if something changed, false if not.
     */
    public boolean somethingIsChanged()
    {
        for (int i = 0; i < this.size(); i++)
        {
            if (this.get(i).getValue().somethingIsChanged())
            {
                return true;
            }
        }

        return false;
    }

    /**
     * makes all cells in the table "fresh," as in new since last revision.
     */
    public void makeFresh()
    {
        for (int i = 0; i < this.size(); i++)
        {
            this.get(i).getValue().makeFresh();
        }
    }

    /**
     * returns the first key in the map.
     * @return the first key
     */
    public String getFirstKey()
    {
        if (this.size() > 0)
        {
            return this.get(0).getKey();
        }
        return null;
    }

    /**
     * returns all row names (first column of row) that starts with the specified string.
     * @param s - the string that prefixes desired rows' names.
     * @return an ArrayList of the names, as strings.
     */
    public ArrayList<String> rowNamesStartingWith(String s)
    {
        Iterator<String> it = map.keySet().iterator();
        ArrayList<String> list = new ArrayList<String>();

        String tmp;

        while (it.hasNext())
        {
            tmp = it.next();
            if (tmp.startsWith(s))
            {
                list.add(tmp);
            }
        }

        return list;
    }

    /**
     * returns a count of the rows that have names (col 0) that are prefixed by the specified string.
     * @param s - the string that prefixes desried row names.
     * @return a number of rows found with that prefix.
     */
    public int numberOfRowsStartingWith(String s)
    {
        return rowNamesStartingWith(s).size();
    }

    /**
     * indexOfPartial Address returns the index of the item with a key
     * that most closely resembles a partial address.
     * A key may be defined for a "scope" item to search around.
     *
     * NOTE: currently goes through whole table. should B-search outward instead!
     *
     * @param partial - a partial name of something
     * @param scope - the name of an item to look around.
     * @return the index, -1 if the item couldn't be found.
     */
    public int indexOfClosestMatch(String partial, String scope)
    {
        ArrayList<String> itemKeys = new ArrayList<String>();

        // get the index of the item to use for scope.
       
        String bestKey = null;
        int bestCompare = Integer.MAX_VALUE;
        int curCompare;
        int ibk = indexByKeyOf(partial);
        String key;

         if (ibk >= 0)
        {
            return ibk;
        }
       
        // get all indexes of things starting or ending with partial.
        for (int i = 0; i < this.size(); i++)
        {
            key = this.get(i).getKey();
            if (key.endsWith(partial))
            {
               itemKeys.add(key);
            }
        }

        if (itemKeys.size() > 0)
        {
            bestKey = itemKeys.get(0);
           
            if (scope != null)
            {
                bestCompare = Math.abs(bestKey.compareTo(scope));
                for (int j = 1; j < itemKeys.size(); j++)
                {
                    curCompare = Math.abs(itemKeys.get(j).compareTo(scope));

                   if (curCompare < bestCompare)
                   {
                       bestCompare = curCompare;
                       bestKey = itemKeys.get(j);
                   }
                }
            }
            return indexByKeyOf(bestKey);
        }
        return -1;
    }

    /**
     * indexOfPartial Address returns the index of the item with a key
     * that most closely resembles a partial address.
     * @param name - the name (or partial name) to look for.
     * @return the index, or -1 if not found.
     */
    public int indexOfClosestMatch(String name)
    {
        return indexOfClosestMatch(name, null);
    }

    @Override
    public String toString()
    {
        StringBuilder builder = new StringBuilder();

        builder.append(this.getClass().getName());
        builder.append(" ");
        builder.append(this.version);
        builder.append(" size = ");
        builder.append(this.size());

        return builder.toString();
    }


}
