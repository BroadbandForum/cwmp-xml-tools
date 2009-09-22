/*
 * File: ModelTableDiffer.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import java.util.Map.Entry;
import threepio.tabler.container.Row;
import threepio.tabler.container.Table;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.TableList;

/**
 * ModelTableDiffer finds the difference between tables, producing Tables that represent a merge
 * between two "a source," and one to put on "overlap."
 * properties of tables' cells are also changed in order for advanced formatting when
 * printing the new tables out (via a Printer object).
 *
 * @author jhoule
 */
public class ModelTableDiffer
{

    /**
     * breaks the input table into mini-tables, of each object in the table.
     * if there is extra stuff before the first object, it will show up as a new table
     * prior to the first object. Things after the last object will be included in its table.
     * @param input - the ModelTable to break up.
     * @param majorItemType - the type that defines a row.
     * @param typeCol - the number of the column where types are listed.
     * @return the list of mini-tables.
     */
    private TableList theBreakup(ModelTable input, String majorItemType, int typeCol)
    {
        System.out.println("breaking up " + input.getVersion());

        TableList list = new TableList();

        ModelTable table = new ModelTable();


        for (int i = 0; i < input.size(); i++)
        {
            if (table.getVersion() == null || table.getVersion().isEmpty())
            {
                table.setVersion(input.get(i).getKey());
            }
            if (input.get(i).getValue().get(typeCol).getData().equalsIgnoreCase(majorItemType))
            {
                if (! table.isEmpty())
                    list.add(table);

                table = new ModelTable();
                table.setVersion(input.get(i).getKey());

            }

            table.put(input.get(i));

        }

        if (!table.isEmpty())
        {
            list.add(table);
        }

        return list;
    }

    /**
     * Does the actual diffing of the tables.
     * @param a - the "newest," primary table.
     * @param b - the "old," secondary table.
     * @param majorItemType - the type that defines a row.
     * @param verColNum - the number of the version column.
     * @return the final, diffed table.
     * @throws Exception - when there is any error.
     */
    public ModelTable diffTable(ModelTable a, ModelTable b, String majorItemType, int verColNum) throws Exception
    {
        Table table, other, diffed = new ModelTable();
        ModelTable result = new ModelTable();

        String name, ver, sVer, key;
        boolean f;
        Row temp;
        Entry<String, Row> ent;

        System.out.println("diffing " + a.getVersion() + " and " + b.getVersion());

        TableList listA = theBreakup(a, majorItemType, 1), listB = theBreakup(b, majorItemType, 1);
        
        for (int i = 0; i < listB.size(); i++)
        {
            // diff each table, if possible.
            // add table to list.

            table = listB.get(i);
            if (!table.isEmpty())
            {
                name = table.get(0).getKey();
                other = listA.getTableStarting(name);

                if (other == null)
                {
                    diffed.put(table);
                } else
                {
                    for (int j = 0; j < table.size(); j++)
                    {
                        key = table.get(j).getKey();
                        if (other.containsKey(key))
                        {
                            temp =  table.get(key).merge(other.get(key), verColNum);
                        }
                        else
                        {
                            temp = table.get(key);
                        }

                        diffed.put(key, temp);

                    }

                    for (int m = 0; m < other.size(); m++)
                    {
                        ent = other.get(m);
                        if (! diffed.containsKey(ent.getKey()))
                        {
                            ent.getValue().makeFresh();
                            diffed.put(ent);
                        }
                    }
                    
                }
            }
        }

        result.put(diffed);

        // add unused portion of list A

        for (int k = 0; k < listA.size(); k++)
        {
            table = listA.get(k);
            if (! result.containsKey(table.getFirstKey()))
            {
                table.makeFresh();
                result.put(table);
            }
        }

        // header should never be new
        temp = diffed.get("HEADER");

        if (temp != null)
        {
            temp.makeStale();
        }

        ver = Tabler.abrevVersion(a.getVersion());
        sVer = Tabler.abrevVersion(ver);

        for (int j = 0; j < result.size(); j++)
        {
            temp = result.get(j).getValue();

            if (temp.somethingIsChanged())
            {
                f = temp.get(verColNum).getFresh();
                temp.set(verColNum, ver);
                if (f)
                {
                    temp.get(verColNum).makeFresh();
                    //temp.get(verColNum).mak
                }
            }

            if (!temp.get(verColNum).getData().equals(sVer))
            {
                temp.makeStale();
            }
        }

        result.setBiblio(a.getBiblio());

        result.setVersion(a.getVersion() + " diffed against " + b.getVersion());

        return result;
    }
}
