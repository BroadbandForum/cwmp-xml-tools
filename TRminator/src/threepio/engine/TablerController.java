/*
 * File: TablerController.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import threepio.tabler.*;
import threepio.container.Doublet;
import threepio.documenter.XDoc;
import threepio.documenter.XDocumenter;
import threepio.filehandling.Importer;
import java.io.File;
import java.io.FileNotFoundException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map.Entry;
import threepio.filehandling.FileIntake;
import threepio.tabler.container.*;

/**
 * TablerController makes use of the Tabler, by wrapping it, in order to make a full table,
 * with versioned rows reflecting the progression from a base document to the specified document.
 * @author jhoule
 * @see Tabler
 */
public class TablerController
{
    /**
     * The tabler that this controller will wrap.
     */
    private ModelTabler myTabler;

    /**
     * Default constructor, requires an IHM of the columns for the tabler
     * that will be created to wrap.
     * @see IndexedHashMap
     * @param cols - the columns to put in the table.
     */
    public TablerController(IndexedHashMap<String, String> cols)
    {
        myTabler = new ModelTabler(cols);
    }

    /**
     * Constructor that wraps the given tabler
     * @param xTabler - the tabler to wrap.
     */
    public TablerController(ModelTabler xTabler)
    {
        myTabler = xTabler;
    }

    /**
     * Creates a table of references, based on the bibliographic document
     * that is passed to it.
     * @param doc - the bibliographic document.
     * @return a Table listing the bibliographic info.
     * @throws Exception - at any problem encountered when making the table.
     */
    public static XTable makeRefTable(XDoc doc) throws Exception
    {
        ModelTabler myTabler;
        IndexedHashMap<String, String> cols = new IndexedHashMap<String, String>();
        XTable temp;
        XTable res = new XTable();
        cols.put("Name", "name");
        cols.put("Title", "title");
        cols.put("Org", "organization");
        cols.put("Category", "category");
        cols.put("Date", "date");
        cols.put("Link", "hyperlink");

        myTabler = new ModelTabler(cols);
        String[] labels =
        {
            "id"
        };
        temp = myTabler.parseContainer(doc, "type", "bibliography", null, labels, null, false);

        for (int i = 0; i < temp.size(); i++)
        {
            temp.get(i).getValue().get(0).prePend("<a name=\"" + temp.get(i).getKey() + "\"></a>");
        }

        res.setVersion(temp.getVersion());
        res.put(myTabler.getHeader());

        res.put(temp);

        res.makeStale();
        return res;
    }

    /**
     * makeWholeTable makes a table for a document (by filename),
     * and one for each old, imported version of the document (recursively).
     *
     * @param ID - the name of the document, NOT the filename.
     * @param path - the path for finding the doucment.
     * @param majorItemType - the type of Item to make rows for.
     * @param insertHeader - to insert a Header row or not, with colum names.
     * @return the table, layered on top of all old versions.
     * @throws java.lang.Exception - when
     */
    public ModelTable makeWholeTable(String ID, String path, String majorItemType, boolean insertHeader) throws Exception
    {
        ModelTable table = null, two = null;
        Importer imp;
        XDocumenter doccer = new XDocumenter();
        XDoc doc, bibDoc;
        Doublet<String, String> tempDoublet;
        IndexedHashMap<String, ModelTable> tables = new IndexedHashMap<String, ModelTable>();
        ExclusiveVersionList<XTable> bibs = new ExclusiveVersionList<XTable>();
        IndexedHashMap<String, String> inputs = new IndexedHashMap<String, String>();
        XTable refTable = null, masterRef = null;
        File file;

        file = FileIntake.resolveFile(new File(path), true);

        if (file == null)
        {
            throw new FileNotFoundException("cannot make a table becuase the file is missing");
        }

        path = file.getPath();

        // put our first document in the list. This is the one a user will be looking for.
        inputs.put(ID, path);
        System.out.println("INFO: adding input " + file.getName());
        System.out.println();

        // go through all inputs, making table for them, IF REQUIRED.
        // if the table has already been processed and added to tables,
        // then just skip it.
        for (int i = 0; i < inputs.size(); i++)
        {
            tempDoublet = new Doublet(inputs.get(i));
            doc = doccer.convertFile(tempDoublet);

            // import the information defined prior to the tabled model.
            imp = new Importer();


            if (!doc.isEmpty())
            {
                imp.importFrom(doc, doc.getVersion());
            }

            if (imp.hasBiblio())
            {
                bibDoc = doccer.convertFile(new File(file.getParent() + FileIntake.fileSep + imp.getBiblio()));
                refTable = makeRefTable(bibDoc);
            } else
            {
                bibDoc = null;
                refTable = null;
            }

            // iterate through the docs that the document depends on,
            // making tables for them and the document
            Iterator<Entry<String, String>> it = imp.getToTable().entrySet().iterator();
            while (it.hasNext())
            {
                tempDoublet = new Doublet(it.next());

                tempDoublet.setValue(file.getParent() + FileIntake.fileSep + tempDoublet.getValue());

                if (!(inputs.containsKey(Tabler.abrevVersion(tempDoublet.getKey()))))
                {
                    // add to queue to process if it hasn't already been processed.
                    inputs.put(tempDoublet);
                    // System.err.println("adding input " + tempDoublet.getKey());
                }
            }

            if (refTable != null)
            {
                bibs.add(refTable);
            }

            // get the table for the ith document
            // System.err.println("making table for " + doc.getVersion());

            table = makeTable(doc, majorItemType, refTable);

            System.out.println("INFO: made table for " + table.getVersion());
            System.out.println();

            // check to see if there were components,
            // iff there were, (and table is emptyish) the table should be
            // the old table, with components inserted, using insertComponents.

            if (!table.getComponents().isEmpty())
            {
                 if (inputs.size() < 2)
                    {
                        throw new Exception("no other inputs to insert into");
                    }

                    two = makeWholeTable(inputs.get(inputs.size() - 1).getKey(),
                            inputs.get(inputs.size() - 1).getValue(), majorItemType, insertHeader);

                     table = insertComponents(two, table.getComponents(), table.getVersion());
            }
            

            table.setBiblio(refTable);
            table.makeStale();

            // put the table on the list of tables.
            tables.put(Tabler.abrevVersion(inputs.get(i).getKey()), table);
        }

        // compile the master bibliographic table
        for (int i = 0; i < bibs.size(); i++)
        {
            if (masterRef == null)
            {
                masterRef = bibs.get(i);
            } else
            {
                for (int j = 0; j < bibs.get(i).size(); j++)
                {
                    if (!(masterRef.containsKey(bibs.get(i).get(j).getKey())))
                    {
                        masterRef.add(bibs.get(i).get(j));
                    }
                }
            }
        }

        table = new ModelTable();

        if (insertHeader)
        {
            table.put(myTabler.getHeader());
            table.get("HEADER").makeStale();
        }
        table.setVersion(ID);

        table.setBiblio(masterRef);
        // then sort and melt the tables into one.
        table.put(sortAndMelt(tables, majorItemType));

        table.getProfiles().put(this.getHeader());
        table.getProfiles().put(scrubProfiles(table));
        table.getProfiles().makeStale();

        return table;
    }

    /**
     * sortAndMelt sorts the tables so that the oldest is first and the newest is last.
     * it then overlaps the tables, using the differ
     * @param tables - the list of tables to work with.
     * @return the table that is the result of the operations.
     * @throws java.lang.Exception - when diffing fails.
     */
    private ModelTable sortAndMelt(IndexedHashMap<String, ModelTable> tables, String majorItemType) throws Exception
    {
        insertionSort(tables);
        return meltingPot(tables, majorItemType);
    }

    /**
     * meltingPot melts the tables together, in sequential order, until the
     * final table is diffed with the results of previous diffs, making it
     * a table representing all of the data of all the tables.
     * THIS CAN ONLY BE USED ON A SORTED LIST OF TABLES.
     * @param tables - the tables to work with.
     * @return the table that is the result of the melting.
     * @throws java.lang.Exception
     */
    private ModelTable meltingPot(IndexedHashMap<String, ModelTable> tables, String majorItemType) throws Exception
    {
        ModelTable result = null;
        ModelTableDiffer differ = new ModelTableDiffer();

        for (int i = 0; i < tables.size(); i++)
        {
            // adding to the old table should make values "fresh,"
            // not residual attributes.
            tables.get(i).getValue().makeStale();

            if (result != null)
            {
                // the result table now has "old" data on it,
                // since there is a new one going into it.
                result.makeStale();
               // System.err.println(tables.get(i).getValue().getDMRs().size());
                result = differ.diffTable(tables.get(i).getValue(), result, majorItemType, myTabler.verColNum());
            } else
            {
                // this is the first table.
                result = tables.get(i).getValue();
            }
        }

        return result;
    }

    /**
     * insertionSort is a sort on an IHM of tables.
     * @param tables - the IHM
     */
    private void insertionSort(IndexedHashMap<String, ModelTable> tables)
    {
        int k;
        Entry<String, ModelTable> temp;
        for (int j = 1; j < tables.size(); j++)
        {
            temp = tables.get(j);
            k = j - 1;
            while (k >= 0 && tables.get(k).getKey().compareTo(temp.getKey()) > 0)
            {
                tables.set(k + 1, tables.get(k));
                k--;
            }
            tables.set(k + 1, temp);
        }
    }

    /**
     * returns the number of the column that has the version in it.
     * @return the number.
     */
    public int verColNum()
    {
        return myTabler.verColNum();
    }

    /**
     * accesses the wrapped Tabler's getHeader method
     * @return the header from the tabler.
     * @see Tabler#getHeader()
     */
    public Doublet<String, Row> getHeader()
    {
        return myTabler.getHeader();
    }

    /**
     * accesses the parsing method of the wrapped Tabler, using this document and reference table.
     * @param doc - the document
     * @param refTable - the reference table for the tabling process.
     * @return the table made by the tabler.
     * @throws Exception - if anything goes wrong when tabling.
     * @see Tabler
     * @see Tabler#parseContainer(threepio.documenter.Doc, java.lang.String, java.lang.String, java.lang.String, java.lang.String[], threepio.tabler.container.XTable, boolean)
     */
    private ModelTable makeTable(XDoc doc, String majorItemType, XTable refTable) throws Exception
    {
        // parse the document into a table.
        return (ModelTable) myTabler.parseContainer(doc, "name", doc.getVersion(), majorItemType, Tabler.stdLabels, refTable, false);
    }

    /**
     * puts the list of components into the table, where they should be.
     * @param t - the table to insert the components into.
     * @param components - the components to insert.
     * @param version - the version the final table is to be set to.
     * @return a table that is the original with the components inserted, with a version of version specified.
     * @throws Exception - when encountering errors finding spots for components in tables.
     */
    private ModelTable insertComponents(ModelTable t, ArrayList<TRComponent> components, String version) throws Exception
    {
        TRComponent comp;
        ModelTable table = new ModelTable(t);
        XTable guts;
        int where;
        HashMap<String, String> params;
        String prevPath;
        String prevObj;

        for (int i = 0; i < components.size(); i++)
        {
            comp = components.get(i);
            params = comp.getParams();
            guts = comp.getTable();

            prevObj = params.get("dmr:previousObject");

            prevPath = params.get("path");
            
            if (prevObj != null)
            {
                prevPath = prevPath + prevObj;
            }
            
            // will find the spot after the previous object.
            where = table.findSpotAfter(prevPath);

            table.put(where, guts);

        }

        table.setVersion(version);

        return table;
    }

    /**
     * removes from the table the rows of the given type, returning those rows as a new table.
     * @param table - the table to scrub
     * @param type - the type of items to remove.
     * @return the removed items, as a table.
     */
    private XTable scrubOf(XTable table, String type)
    {
        int tCol = myTabler.typeColNum();

        XTable scrubbed = new XTable();

        for (int i = 0; i < table.size(); i++)
        {
            if (table.get(i).getValue().get(tCol).getData().equalsIgnoreCase(type))
            {
                scrubbed.put(table.remove(i--));
            }
        }

        return scrubbed;
    }

    /**
     * removes and returns all rows that define a Profile object.
     * @param table
     * @return the table without the Profile objects.
     */
    private XTable scrubProfiles(XTable table)
    {
        return scrubOf(table, "Profile");
    }

    /**
     * shortcut to the tabler's typeColNum()
     * @return the index of the column that defines the type of object in a row, -1 if there isnt' one.
     * @see Tabler#typeColNum() 
     */
    public  int typeColNum()
    {
        return myTabler.typeColNum();
    }
}
