/*
 * File: Tabler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import threepio.container.Doublet;
import threepio.documenter.Doc;
import threepio.documenter.XTag;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;
import threepio.tabler.container.Table;
import threepio.tabler.container.XTable;

/**
 * A Tabler converts a Document to a XTable,
 * based on a user-defined or designer-defined list of columns.
 *
 * @author jhoule
 */
public abstract class Tabler
{
    /**
     * The name for all Header (column name) rows.
     */
    public static String HEADER_ROW_NAME = "HEADER";
    /**
     * a table for associations of items in XML with Column names.
     */
    IndexedHashMap<String, String> columns;
    /**
     * a table of things to mirror, in case a column is missing for one, and they are similar.
     * currently only used for names and bases.
     */
    HashMap<String, String> substitutes;
    /**
     * the heading of the column to put versions into.
     */
    static String VER_COL_NAME = "Version";

    List<String> nonStandards;

    /**
     * The standard labels to use to label a row.
     */
    public static String[] stdLabels =
    {
        "name", "base"
    };

    /**
     * no-argument constructor.
     * constructs all internal structures with default options and values.
     */
    public Tabler()
    {
        substitutes = new HashMap<String, String>();
        setupSubstitutes();
        columns = new IndexedHashMap<String, String>();
    }

    /**
     * constructor that takes in an IHM for column settings.
     * @param cols
     */
    public Tabler(IndexedHashMap<String, String> cols)
    {
        this();
        columns = cols;
        nonStandards = new ArrayList<String>();
    }

     /**
     * constructor that takes in an IHM for column settings, List of specials.
     * @param specials - a list of special values made by the programmer to use when Tabling.
     * @param cols
     */
    public Tabler(IndexedHashMap<String, String> cols, List<String> specials)
    {
        this();
        columns = cols;
        nonStandards = specials;
    }

    /**
     * returns an abbreviated version string for BBF documents,
     * stripping off names, and leaving numbers.
     * If it doesn't appear to be a BBF version, the passed string is returned.
     * @param vers - the original version string
     * @return the new version string
     */
    public static String abrevVersion(String vers)
    {
        int temp;

        if (vers.contains(":"))
        {
            temp = vers.indexOf(':');

            return vers.substring(temp + 1);

        }
        return vers;
    }

    /**
     * gets the tables of the components defined in a document, that are
     * required for the given model, with addresses like "IGD.FOO.BAR"
     * @param doc - the document.
     * @param model - the model to get components for.
     * @return the list of tables for the components defined in the document.
     * @throws Exception - when encountering a problem with a file.
     */
    abstract protected Table getComponents(Doc doc, String model) throws Exception;

    /**
     * sets up the value re-assignments
     */
    abstract void setupSubstitutes();

    /**
     * parseContainer parses a "container" XML body out of a Doc.
     * @param d - the doc
     * @param param - the parameter to identify the container by
     * @param paramValue - the value of the parameter to identify the container by.
     * @param orderedLabels - the labels to use for rows, in order from most prominent to least.
     * @param refTable - the reference table to use.
     * @param includeContainer - wether to include the container element.
     * @return a table of the information parsed.
     * @throws Exception upon anything that would keep him from table being made.
     */
    abstract Table parseContainer(Doc d, String param, String paramValue, String MajorItemType, String[] orderedLabels, XTable refTable, boolean includeContainer) throws Exception;

    /**
     * shortcut for parseContainer with less variables.
     * @param d - the doc
     * @param param - the parameter to identify the container by
     * @param paramValue - the value of the parameter to identify the container by.
     * @param refTable - the reference table to use.
     * @param includeContainer - wether to include the container element.
     * @return a table of the information parsed.
     * @see #parseContainer(threepio.documenter.Doc, java.lang.String, java.lang.String, java.lang.String, java.lang.String[], threepio.tabler.container.XTable, boolean) 
     * @throws Exception
     */
    public Table parseContainer(Doc d, String param, String paramValue, XTable refTable, boolean includeContainer) throws Exception
    {
        return parseContainer(d, param, paramValue, null, stdLabels, refTable, includeContainer);
    }

    /**
     * shortcut for parseContainer with less variables.
     * @param d - the doc
     * @param param - the parameter to identify the container by
     * @param paramValue - the value of the parameter to identify the container by.
     * @param includeContainer - wether to include the container element.
     * @return a table of the information parsed.
     * @see #parseContainer(threepio.documenter.Doc, java.lang.String, java.lang.String, java.lang.String, java.lang.String[], threepio.tabler.container.XTable, boolean) 
     * @throws Exception
     */
    public Table parseContainer(Doc d, String param, String paramValue, boolean includeContainer) throws Exception
    {
        return parseContainer(d, param, paramValue, null, stdLabels, null, includeContainer);
    }

    /**
     * returns true if the tag is a descriptive tag, as found in columns.
     * @param tag - the tag to inspect.
     * @return true if the tag was descriptive.
     */
    boolean tagIsColumn(XTag tag)
    {
        return columns.containsValue(tag.getType().toLowerCase());
    }

    /**
     * returns true if the document passed can be parsed by the class. false if not.
     * @param d - the document that will be parsed.
     * @return true if the document can be parsed, false if not.
     */
    public abstract boolean canParse(Doc d);

    /**
     * creates a header row Doublet.
     * @return the Doublet, with a
     */
    public Doublet<String, Row> getHeader()
    {
        Row row = new Row(columns.size());
        for (int i = 0; i < columns.size(); i++)
        {
           
            row.set(i, columns.get(i).getKey());
        }

        return new Doublet<String, Row>(HEADER_ROW_NAME, row);
    }

    /**
     * returns the number of the column that is used for versioning, or -1 if it cannot be found.
     * @return the number, -1 if the column doesn't exist.
     */
    public int verColNum()
    {
        return this.columns.indexByKeyOf(VER_COL_NAME);
    }

    /**
     * returns the number of the column that is used for typing, or -1 if it cannot be found.
     * @return the number, -1 if the column doesn't exist.
     */
    public int typeColNum()
    {
        return this.columns.indexByKeyOf("Type");
    }
}
