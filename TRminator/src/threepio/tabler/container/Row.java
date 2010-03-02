/*
 * File: Row.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import java.util.ArrayList;
import java.util.HashMap;

/**
 * Row is a row in a table.
 * It containsInCell an array of column contents.
 * Only SETTING is allowed. ADDING is not.
 * @author jhoule
 */
public class Row extends ArrayList<StringCell>
{
    /**
     * any attributes that the the programmer sees fit to add to the row.
     */
    private HashMap<String, String> attributes;

    /**
     * any extra objects that the programmer sees fit to add to the row.
     */
    private ArrayList<Object> bucket;

    /**
     * The real size of the row, regardless of what happens to the underlying
     * Arraylist. Since this should be the only thing that can add to it.
     */
    private int capacity;
    /**
     * a Row can be "empty" even when the underlying arraylist has items in it,
     * such as cells that were initialized to blank strings.
     */
    private boolean empty;

    /**
     * the text that should be inside a cell if it's blank.
     */
    public static String BLANK_CELL_TEXT = Table.BLANK_CELL_TEXT;

    /**
     * The only public constructor for row, where the capacity is defined at construction time.
     * @param size - the capacity of this row
     */
    public Row(int size)
    {
        capacity = size;
        empty = true;
        attributes = new HashMap<String, String>();
        bucket = new ArrayList<Object>();

        for (int i = 0; i < size; i++)
        {
            this.privateAdd(BLANK_CELL_TEXT);
        }
    }

    /**
     * A private copy constructor. Not really a fully copy, because references
     * to cells are the same, and cells are not duplicated.
     * @param row - the row to take info from.
     */
    private Row(Row row)
    {
        capacity = row.capacity;
        empty = row.empty;
        attributes = row.attributes;
        bucket = row.bucket;

        this.addAll(row);
    }

    /**
     * adding overridden to keep row from being externally modified.
     * @param e - the cell one would try to add.
     * @return an unsupported operation exception, ALWAYS.
     */
    @Override
    public boolean add(StringCell e)
    {
        throw new UnsupportedOperationException("no adding!");
    }

    /**
     * Adds a new StringCell with the string inside it. Only should be used
     * by the constructor.
     * @param e - the String to put in the new Cell.
     * @return true if the adding was allowed, false if not, or if there was another problem
     * when adding in the superclass.
     */
    private boolean privateAdd(String e)
    {
        // allow only adding blanks, for constructor.
        if (e.equals(BLANK_CELL_TEXT) && super.size() <= capacity)
        {
            return super.add(new StringCell(e));
        }

        return false;
    }

    /**
     * returns the capacity, rather than whatever size the arraylist becomes.
     * @return the capacity (not always the size)
     */
    @Override
    public int size()
    {
        return capacity;
    }

    /**
     * Returns true if the Row was is empty.
     * @return true if the Row is empty, false if not.
     */
    @Override
    public boolean isEmpty()
    {
        return empty;
    }

    /**
     * Checks if the first (most likely a naming) column has been filled in the row.
     * Returns true if so. false if not.
     * @return true if the first column is filled, false if it is not.
     */
    public boolean hasFirstColFilled()
    {
        return (this.get(0) != null && !this.get(0).equals(BLANK_CELL_TEXT));
    }

    /**
     * Setting a location to a String, Overridden so that the empty flag is flipped.
     * @param index - where to put it
     * @param element - what to put there
     * @return true if the thing was put there, false if not.
     */
    public String set(int index, String element)
    {
        return set(index, element, false);
    }

    /**
     * Sets the cell's data to the passed string, at the location passed, and sets that cell's flag.
     * @param index - where the cell is
     * @param element - the string to set the data to.
     * @param flag - the flag to set the cell's special flag to.
     * @return the old data from the cell.
     */
    public String set(int index, String element, boolean flag)
    {
        String old = get(index).data;
        empty = false;

        get(index).set(element, flag);

        return (old);
    }

    /**
     * Sets the cell's data to the passed string ONLY.
     * DO NOT USE INSIDE THREEPIO.
     * Helps for wrapping the text, etc
     * @param index - index of cell to modify
     * @param element - data to insert into cell.
     * @return the cell's old data.
     */
    public String silentSet(int index, String element)
    {
        String old = get(index).data;
        empty = false;

        get(index).silentSet(element);

        return (old);
    }

    /**
     * merges the row with another, DOES NOT ACCOUNT FOR VERSIONS.
     * if no differences are found, the row is left completely alone.
     * The result of the merge is returned as a new row.
     *
     * @param overLap - the "newer" table to compare this to, and replace information with.
     * @param verCol - the index of the column where a version is set for the row.
     * @return a new row that is the product of the merge.
     * @throws java.lang.Exception - when the rows are not compatible
     */
    public Row merge(Row overLap, int verCol) throws Exception
    {
        String data;

        Row theRow = new Row(this);

        // boolean changeVer = false;

        if (overLap.size() != this.size())
        {
            throw new Exception("sizes do not match!");
        }
        for (int i = 0; i < this.size(); i++)
        {
            // if there's a difference here, and it's not the version column,
            if (i != verCol && theRow.get(i).data.compareTo(overLap.get(i).getData()) != 0 && !overLap.get(i).getData().equals(BLANK_CELL_TEXT))
            {
                if (overLap.get(i).special)
                {
                    // append the cell's data to the old data
                    data = theRow.get(i).data + " " + overLap.get(i).data;

                } else
                {
                    // replace the cell's data with that of the new table.
                    data = overLap.get(i).getData();
                }

                theRow.get(i).set(data);
                theRow.get(i).changed = true;
                // replace the version cell's data with the new version.
                //    changeVer = true;
            }
        }

        return theRow;
    }

    /**
     * makes all parts of the row stale (turns off their fresh flag)
     */
    public void makeStale()
    {
        for (int i = 0; i < this.size(); i++)
        {
            this.get(i).makeStale();
        }
    }

    /**
     * makes all parts of the row fresh (turns on their fresh flag)
     */
    public void makeFresh()
    {
        for (int i = 0; i < this.size(); i++)
        {
            this.get(i).makeFresh();
        }
    }

    /**
     * returns if anthing in the row has its fresh flag on.
     * @return true if anything is frsh, false if not.
     */
    @SuppressWarnings("empty-statement")
    public boolean getAllCellsFresh()
    {
        int i = 0;

        for (i = 0; i < size() && (get(i).fresh); i++);

        return (i >= this.size());
    }

    /**
     * returns if anything in the row has its changed flag on.
     * @return true if there's a changed cell, false if there isn't.
     */
    public boolean somethingIsChanged()
    {
        for (int i = 0; i < this.size(); i++)
        {
            if (this.get(i).changed)
            {
                return true;
            }
        }

        return false;
    }

    /**
     * returns the parameters hashmap.
     * @return the parameters map.
     */
    public HashMap<String, String> getParams()
    {
        return attributes;
    }

    @Override
    public StringCell remove(int index)
    {
        StringCell c = super.remove(index);

       if (c != null)
       {
           --capacity;
       }

        return c;
    }

    @Override
    public boolean remove(Object o)
    {
        StringCell c = (StringCell) o;
       if (super.remove(c))
       {
           --capacity;
           return true;
       }
       return false;
    }

    /**
     * Returns true if a cell's data from this row contains the passed string.
     * @param s - the string to check for.
     * @return true if the string is in the cell's data, false if not.
     */
    @SuppressWarnings("empty-statement")
    public boolean containsInCell(String s)
    {
        int i = 0;
        for (i = 0; i < this.size() && !this.get(i).contains(s); i++);

        if (i < this.size())
            return true;

        return false;
    }

    /**
     * adds an Object to the "bucket" of extra Objects the programmer may use.
     * @param o - the object to add to the "bucket."
     */
    public void addToBucket(Object o)
    {
        bucket.add(o);
    }

    /**
     * returns the "bucket" of objects the programmer may use.
     * @return the "bucket."
     */
    public ArrayList<Object> getBucket()
    {
        return bucket;
    }
}
