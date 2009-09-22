/*
 * File: XTable.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import java.util.ArrayList;
import threepio.documenter.XDoc;

/**
 * XTable is a Table for XML documents.
 * @author jhoule
 */
public class XTable extends Table
{

    /**
     * A list of the Components found in the Table or for the Table.
     */
    protected ArrayList<TRComponent> components;
    /**
     * storage for associated documents
     */
    protected XDoc infoBefore, infoAfter, whole;

    /**
     * no-argument constructor
     * constructs infoBefore and infoAfter as new XDocs.
     */
    public XTable()
    {
        super();

        infoBefore = new XDoc();
        infoAfter = new XDoc();
    }

    /**
     * gets the information following the table as a document.
     * @return the document.
     */
    public XDoc getInfoAfter()
    {
        return infoAfter;
    }

    /**
     * copy constructor
     * @param t - the table to copy.
     */
    public XTable(XTable t)
    {
        super(t);
        this.whole = t.whole;
        this.infoBefore = t.infoBefore;
        this.infoAfter = t.infoAfter;
    }

    /**
     * sets the information following the table
     * @param after - the information to set
     */
    public void setInfoAfter(XDoc after)
    {
        infoAfter = after;
    }

    /**
     * constructor that associates the Xtable with the document passed.
     * @param doc - the doc to associate with the table.
     */
    public XTable(XDoc doc)
    {
        super();

        this.whole = doc;
        infoBefore = new XDoc();
        infoAfter = new XDoc();
    }

    /**
     * adds all parts of the Xtable passed to this XTable.
     * @param t - another XTable
     */
    public void put(XTable t)
    {
        this.infoBefore.addAll(t.infoBefore);
        super.put(t);
    }

    /**
     * sets the doc to associate this table with.
     * @param d - the XDoc to associate with this table.
     */
    public void setDoc(XDoc d)
    {
        whole = d;
    }

    /**
     * returns the Doc that this table is associated with.
     * @return the Doc.
     */
    public XDoc getDoc()
    {
        return whole;
    }

    /**
     * sets the info before this table.
     * @param before - the Document to set the before document to.
     */
    public void setInfoBefore(XDoc before)
    {
        infoBefore = before;
    }

    /**
     * gets the data from row 0, col 0.
     * @return the data from 0, 0.
     */
    public String getFirstCellData()
    {
        if (this.size() > 0)
        {
            return this.get(0).getValue().get(0).data;
        }
        return null;
    }

    /**
     * returns true if the XTable's data in 0,0 is equal to the string.
     * @param s - the string to check for.
     * @return true if the table starts with the string, false if not.
     */
    public boolean startsWith(String s)
    {
        String data = getFirstCellData();

        if (data != null)
        {
            return (data.equals(s));
        }

        return false;
    }

    /**
     * finds the index of the spot after the object(s) starting with the specified path.
     * @param path - the path to be looking for.
     * @return the index of the spot in the table after the item and children.
     * @throws Exception if the path doesn't exist.
     */
    public int findSpotAfter(String path) throws Exception
    {
        int spot = indexByKeyOf(path);
        String endingSepRemoved = path;

        if (path.endsWith(String.valueOf(SEPARATOR)))
        {
            endingSepRemoved = path.substring(0, path.lastIndexOf(SEPARATOR));
        }

        int otherSpot = indexByKeyOf(endingSepRemoved);

        if (spot < 0)
        {
            spot = otherSpot;

            if (spot < 0)
            {
                throw new Exception("previous thing: " + path + " does not exist");
            }
        }

        return spot + (numberOfRowsStartingWith(endingSepRemoved));
    }

    /**
     * findSpot finds a spot in a table for an object with given path.
     * @param path - the path for the object to place
     * @return an index where the item should go
     * @throws Exception - when a required object cannot be found.
     */
    public int findSpot(String path) throws Exception
    {
        int spot = indexByKeyOf(path);

        if (spot < 0)
        {

            int end = path.lastIndexOf(SEPARATOR);
            if (path.endsWith("."));
            {
                end = path.substring(0, end).lastIndexOf(SEPARATOR);
            }

            String objPath = path.substring(0, end) + SEPARATOR;

            if (containsKey(objPath))
            {
                return indexByKeyOf(objPath) + numberOfRowsStartingWith(objPath);
            } else
            {
                throw new Exception("Parent object " + objPath + " missing!");
            }
        }

        return spot;
    }

    /**
     * returns a table of components that were extracted from the document
     * that the table was made from.
     * @return the table of components. could be empty or null.
     */
    public ArrayList<TRComponent> getComponents()
    {
        return components;
    }

    /**
     * sets the table of components that ewre found when composing the table.
     * @param cs - the table of components.
     */
    public void setComponents(ArrayList<TRComponent> cs)
    {
        components = cs;
    }

    /**
     * removes empty columns from a table.
     * @throws Exception when the size of the table is below 1.
     */
    public void StripEmptyCols() throws Exception
    {
        // check if there are rows to work on.
         if (this.size() < 1)
        {
            throw new Exception("No rows to edit");
        }

        int start;
        Row row;
        String str;
        ArrayList<Boolean> empties = new ArrayList<Boolean>();

        // skip the header, if present.
        if (this.get(0).getKey().equalsIgnoreCase("HEADER"))
        {
            start = 1;
        }
        else
        {
            start = 0;
        }

        for (int k = 0; k < this.get(0).getValue().size(); k++)
        {
           empties.add(Boolean.TRUE);
        }

        for (int i = start; i < this.size(); i++)
        {
            row = this.get(i).getValue();

            for (int j = 0; j < row.size(); j++)
            {
                str = row.get(j).getData();

                if (!(str == null || str.isEmpty() || str.equals(Table.BLANK_CELL_TEXT)))
                {
                   empties.set(j, Boolean.FALSE);
                }
            }
        }

        // empties[m] is true if it's empty.

        for (int m = 0; m < empties.size();)
        {
            if (empties.get(m))
            {
                for (int i = 0; i < this.size(); i++)
                {
                    row = this.get(i).getValue();

                    row.remove(m);
                }
                empties.remove(m);
            }
            else
            {
                m++;
            }
        }
    }
}
