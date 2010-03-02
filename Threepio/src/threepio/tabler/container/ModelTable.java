/*
 * File: ModelTable.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler.container;

import threepio.documenter.XDoc;

/**
 * A ModelTable is an XTable with a bibliographic table inside.
 * @author jhoule
 * @see XTable
 * @see Table
 */
public class ModelTable extends XTable {

    /**
     * the bibliographic table to associate with this table.
     */
    private XTable biblio;
    /**
     * the profiles that are associated with this table.
     */
    private XTable profiles;

    /**
     * no-argument constructor, does XTable's construction.
     */
    public ModelTable() {
        super();
    }

    /**
     * constructor with a document to associate with the table.
     * @param doc - the document to associate.
     */
    public ModelTable(XDoc doc) {
        super(doc);
    }

    /**
     * copy constructor
     * @param t - another ModelTable to copy from.
     */
    public ModelTable(ModelTable t) {
        super(t);
        biblio = t.biblio;
    }

    /**
     * sets the bibliographic table to the passed table.
     * @param bib - the table to set it to.
     */
    public void setBiblio(XTable bib) {
        biblio = bib;
    }

    /**
     * gets the bibliographic table
     * @return the bibliographic table.
     */
    public XTable getBiblio() {
        return biblio;
    }

    /**
     * places another. table in a spot on the table.
     * @param where - the index where to insert the other table into this one.
     * @param guts - the other table to put into this one.
     */
    public void put(int where, XTable guts) {
        if (where < 0 || where > this.size())
        {
            throw new ArrayIndexOutOfBoundsException(where);
        }

        int j = where;
        for (int i = 0; i < guts.size(); i++) {
            this.put(j++, guts.get(i));
        }
    }

    /**
     * retursn the table of profiles that may or may not be associated with this table.
     * @return the profiles, as a table. empty table is possible.
     */
    public XTable getProfiles() {
        if (profiles == null) {
            profiles = new XTable();
        }

        return profiles;
    }
}
