/*
 * File: TablerController.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.engine;

import threepio.container.ExclusiveVersionList;
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
import threepio.tagHandler.*;

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
    public TablerController(ColumnMap cols)
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
        ColumnMap cols = new ColumnMap();
        XTable temp;
        XTable res = new XTable();
        StringBuffer buff;

        NameHandler nh = new NameHandler();
        TitleHandler th = new TitleHandler();
        OrganizationHandler oh = new OrganizationHandler();
        CategoryHandler ch = new CategoryHandler();
        HyperlinkHandler hh = new HyperlinkHandler();


        cols.put(nh.getFriendlyName(), nh.getTypeHandled());
        cols.put(th.getFriendlyName(), th.getTypeHandled());
        cols.put(oh.getFriendlyName(), oh.getTypeHandled());
        cols.put(ch.getFriendlyName(), ch.getTypeHandled());
        cols.put("Date", "date");
        cols.put(hh.getFriendlyName(), hh.getTypeHandled());

        myTabler = new ModelTabler(cols);
        String[] labels =
        {
            "id"
        };
        temp = myTabler.parseContainer(doc, "type", "bibliography", null, labels, null, false);

        for (int i = 0; i < temp.size(); i++)
        {

//            if (temp.get(i).getKey().contains("OUI"))
//            {
//                System.err.println();
//            }

            buff = new StringBuffer();
            buff.append("<a name=\"" + temp.get(i).getKey() + "\">");
            buff.append(temp.get(i).getValue().get(0).getData());
            buff.append("</a>");

            temp.get(i).getValue().get(0).silentSet(buff.toString());
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
     * @throws Exception when file-related errors occurr.
     */
    public ModelTable makeWholeTable(String ID, String path, String majorItemType, boolean insertHeader) throws Exception
    {
        return makeWholeTable(ID, path, majorItemType, insertHeader, new ExclusiveVersionList<XTable>());
    }

    /**
     * helper for makeWholeTable(String, String, String, boolean).
     *
     * @param ID - the name of the document, NOT the filename.
     * @param path - the path for finding the doucment.
     * @param majorItemType - the type of Item to make rows for.
     * @param insertHeader - to insert a Header row or not, with colum names.
     * @param bibs - tables for bibliographic information.
     * @return the table, layered on top of all old versions.
     * @throws java.lang.Exception - when file-related errors occurr.
     */
    private ModelTable makeWholeTable(String ID, String path, String majorItemType, boolean insertHeader, ExclusiveVersionList<XTable> bibs) throws Exception
    {
        ModelTable table = null, two = null;
        Importer imp;
        XDocumenter doccer = new XDocumenter();
        XDoc doc, bibDoc = null;
        Doublet<String, String> tempDoublet;
        IndexedHashMap<String, ModelTable> tables = new IndexedHashMap<String, ModelTable>();
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
            tempDoublet = new Doublet<String, String>(inputs.get(i));
            doc = doccer.convertFile(tempDoublet);

            imp = new Importer();

            if (!doc.isEmpty())
            {
                imp.importFrom(doc, doc.getVersion());
            }

            // do bib stuff
            setbibRefs(imp, file, bibs, refTable, doc, bibDoc);

            // iterate through the docs that the document depends on,
            // making tables for them and the document
            inputs = compileInputs(imp, file, inputs);

            table = makeTable(doc, majorItemType, refTable);

            System.out.println("INFO: made table for " + table.getVersion() + "\nsize = " + table.size());
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
        masterRef = makeMasterRef(masterRef, bibs);

        // make the actual table.
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
     * Compiles a list of tables based on the tables that the file references
     * and/or that the tabler needs to make the table for the file.
     * @param imp - the importer that was used on the file.
     * @param file - the file that is being tabled.
     * @param inputs - the list of tables already made. This is modified!!
     * @return the modified list of tables.
     */
    private IndexedHashMap<String, String> compileInputs(Importer imp, File file, IndexedHashMap<String, String> inputs)
    {
        Doublet<String, String> tempDoublet;
        Iterator<Entry<String, String>> it = imp.getToTable().entrySet().iterator();
        while (it.hasNext())
        {
            tempDoublet = new Doublet<String, String>(it.next());

            tempDoublet.setValue(file.getParent() + FileIntake.fileSep + tempDoublet.getValue());

            if (!(inputs.containsKey(Tabler.abrevVersion(tempDoublet.getKey()))))
            {
                // add to queue to process if it hasn't already been processed.
                inputs.put(tempDoublet);
                // System.err.println("adding input " + tempDoublet.getKey());
            }
        }

        return inputs;
    }

    /**
     * Imports the documents requried for bibliographic information
     * and updates the pointers for the bibliograhic document and reference table.
     * @param imp - the intatntiated importer that has already imported from a document.
     * @param file - the main file the table is being made from.
     * @param bibs - the list of tables containing bibliographic information
     * @param refTable - the pointer for the reference table for the main document.
     * @param doc - the pionter for the main document.
     * @param bibDoc - the pointer for the bibliographic document for the main document.
     * @throws Exception - upon an importing failure.
     */
    private void setbibRefs(Importer imp, File file, ExclusiveVersionList<XTable> bibs, XTable refTable, XDoc doc, XDoc bibDoc) throws Exception
    {
        // import the information defined prior to the tabled model.
        XDocumenter doccer = new XDocumenter();

        if (imp.hasBiblio())
        {
            if (bibs.containsVersion(imp.getBiblio()))
            {
                // we already have this information, don't re-make anything.
                refTable = bibs.get(imp.getBiblio());
            } else
            {
                // make new doc and table for biblio information.
                bibDoc = doccer.convertFile(new File(file.getParent() + FileIntake.fileSep + imp.getBiblio()));
                refTable = makeRefTable(bibDoc);

                if (refTable != null)
                {
                    // the table was made, so add it to the library.
                    bibs.add(refTable);
                }
            }
        } else
        {
            bibDoc = null;
            refTable = null;
        }
    }

    /**
     * helper for makeWholeTable.
     * Compiles or re-compiles a master reference table.
     * @param masterRef - the master reference table (or null)
     * @param bibs - the list of bibliographic documents.
     * @return - an XTable of all reference information.
     */
    private XTable makeMasterRef(XTable masterRef, ExclusiveVersionList<XTable> bibs)
    {
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

        return masterRef;
    }

    /**
     * sortAndMelt sorts the tables so that the oldest is first and the newest is last.
     * it then overlaps the tables, using the differ
     * @param tables - the list of tables to work with.
     * @param majorItemType - the type that the body of the table represents.
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
     * @param majorItemType - the type that the body of the table represents.
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
     * @param majorItemType - the top-level type for the document.
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
    public int typeColNum()
    {
        return myTabler.typeColNum();
    }
}
