/*
 * File: ModelTabler.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.tabler;

import threepio.documenter.Doc;
import threepio.documenter.XDoc;
import java.util.ArrayList;
import java.util.HashMap;
import threepio.documenter.XTag;
import java.util.Iterator;
import java.util.Map.Entry;
import java.util.logging.Level;
import java.util.logging.Logger;
import threepio.tabler.container.IndexedHashMap;
import threepio.tabler.container.Row;
import threepio.tabler.container.ModelTable;
import threepio.tabler.container.TRComponent;
import threepio.tabler.container.Table;
import threepio.tabler.container.XTable;
import threepio.tagHandler.DescriptionHandler;
import threepio.tagHandler.HandlerFactory;
import threepio.tagHandler.TagHandler;

/**
 * ModelTabler is a specialized Tabler for converting Threepio Documents to Threepio Tables.
 * It is built around using Threepio for conversio from BBF data models to HTML tables.
 * 
 * @author jhoule
 */
public class ModelTabler extends Tabler
{

    /**
     * the column number for looking up and storing versions.
     */
    String version;

    /**
     * ModelTabler is a tabler for BBF models
     * @param cols - an IHM of the columns that the table should contain.
     */
    public ModelTabler(IndexedHashMap<String, String> cols)
    {
        super(cols);
    }

    /**
     * If a componentTag containsInCell a parameter that should be named differently
     * for tabling purposes, add them to the subs table, and they will be handled
     * after each componentTag parse.
     */
    @Override
    void setupSubstitutes()
    {
        // put entries in where:
        // key = key needed for table
        // value = name of key that should exist

        this.substitutes.put("name", "base");
    }

    /**
     * parseContainer parses a "container" XML body out of a Doc. into an Xtable.
     * @param doc - the doc
     * @param param - the parameter to identify the container by
     * @param paramValue - the value of the parameter to identify the container by.
     * @param majorItemType - the highest level type. for labeling.
     * @param orderedLabels - the labels to use for rows, in order from most prominent to least.
     * @param refTable - the reference table to use.
     * @param includeOuter - wether to include the container element.
     * @return a table of the information parsed.
     * @throws Exception upon anything that would keep from table being made.
     */
    @SuppressWarnings("empty-statement")
    protected XTable parseContainer(XDoc doc, String param, String paramValue, String majorItemType, String[] orderedLabels, XTable refTable, boolean includeOuter) throws Exception
    {
        // make a copy of this one, to protect the original from modification.
        XDoc d = new XDoc(doc);
        // grab the version from this document.
        HashMap<String, String> parameters = null;
        XTable table = new ModelTable(doc);
        Row row = null;
        String v = null;
        int w = 0;
        XTag t = null;
        String containerType = null;
        XDoc before = new XDoc(), after = new XDoc();
        TagHandler h = null;
        HandlerFactory f = new HandlerFactory();
        String curRowName = null, prevRowName = null, prevMajor = "", majorItemName = "", dmr = null;
        boolean inside = false;
        Object x;
        
        String sepStr = Path.delim;
        version = doc.getVersion();

        x = d.poll();

        if (x == null)
        {
            System.err.println("nothing in document?");
            throw new Exception("Document is unreadable.");
        }

        while (!d.isEmpty() && !inside)
        {
            if (x instanceof XTag)
            {

                t = importTag(x);

                if (t.getParams().get(param) != null && t.getParams().get(param).equals(paramValue))
                {
                    inside = true;
                    containerType = t.getType();

                }
            }

            if (!inside)
            {
                before.add(x);

                x = d.poll();
            }
        }

        // put that collected info before the actual table.
        table.setInfoBefore(before);
        row = new Row(columns.size());

        if (d.isEmpty())
        {
            System.err.println("out of document to parse");
        }
        if (!includeOuter || x == null)
        {
            x = d.poll();
        }

        t = importTag(x);

        // System.err.println("XDocTabler is tabling " + paramValue);
        while (inside)
        {

            if (curRowName != null && !(tagIsColumn(t)))
            {
                prevRowName = curRowName;


            }

            if (!(tagIsColumn(t)) && !t.isCloser())
            {
                // get the name for the row.

                dmr = getDMR(t);

                if (dmr != null && dmr.isEmpty())
                {
                    // This isn't working correctly.
                    // "Services" shoots to the top. Is it an issue in the XML?
                    dmr = majorItemName;
                }

                prevMajor = majorItemName;
                curRowName = null;
                for (int i = 0; (i < orderedLabels.length && curRowName == null); i++)
                {
                    curRowName = t.getParams().get(orderedLabels[i]);

                }



                if (!(curRowName == null || majorItemType == null))
                {

                    if (t.getType().equalsIgnoreCase(majorItemType))
                    {
                        majorItemName = curRowName;

                    } else
                    {
                        if (t.getType().equalsIgnoreCase("Profile"))
                        {
                            majorItemName = majorItemName.substring(0, majorItemName.indexOf(sepStr) + 1);
                        }

                        curRowName = majorItemName + curRowName;


                    }
                }


            }
            // closer tags mean the row is done.
            // descriptor's closer tags should NOT be around.
            if (t.isCloser())
            {

                // add row if there is one.
                if (!row.isEmpty() && row.hasFirstColFilled())
                {

                    if (prevRowName == null)
                    {
                        System.err.println("a row exists without a name");
                    }


                    // System.out.println("placing row: " + prevRowName);
                    table.put(prevRowName, row);

                    if (dmr != null)
                    {
                        // add information as to where to put this table later.
                        table.addDmr(prevRowName, dmr);
                    }

                    row = new Row(columns.size());

                    if (t.getType().equalsIgnoreCase(majorItemType) && majorItemName.indexOf(sepStr) != majorItemName.lastIndexOf(sepStr))
                    {
                        majorItemName = majorItemName.substring(0, majorItemName.lastIndexOf(sepStr));
                        majorItemName = majorItemName.substring(0, majorItemName.lastIndexOf(sepStr));
                    }
                }

            } else
            {
                if (tagIsColumn(t))
                {
                    // there is stuff to be parsed to make this a row entry

                    w = columns.indexByValOf(t.getType());

                    try
                    {
                        h = f.getHandler(t);
                    } catch (Exception ex)
                    {
                        Logger.getLogger(ModelTabler.class.getName()).log(Level.SEVERE, "some code went unhandled.", ex);
                        throw new Exception("could not handle a tag of type: " + t.getType());
                    }

                    if (h != null)
                    {
                        // parse and pop all info related to this componentTag. (including t and closer for t)
                        // handler now adds relevant info to row, at w.

                        h.handle(d, before, t, columns, row, w);
                    }
                } else
                {
                    // this is something new, add last row if it isn't empty.

                    if (!row.isEmpty() && row.hasFirstColFilled())
                    {
                        // System.out.println("placing row: " + prevRowName);
                        table.put(prevRowName, row);

                        if (dmr != null)
                        {
                            // add information as to where to put this table later.
                            table.addDmr(prevRowName, dmr);
                        }

                        row = new Row(columns.size());
                    }

                    // if there's a type column, set it to the componentTag's getType.
                    int j = -1;
                    for (j = 0; (j < columns.size() && !columns.get(j).getKey().equalsIgnoreCase("type")); j++);

                    if (j >= 0 && j < columns.size() && !t.getType().equalsIgnoreCase("parameter"))
                    {
                        row.set(j, t.getType());
                    }

                    // parse attributes from componentTag into row
                    parameters = t.getParams();

                    // only put in the info needed for each column.
                    for (int i = 0; i < columns.size(); i++)
                    {
                        v = columns.get(i).getValue();

                        if (parameters.containsKey(v))
                        {
                            // componentTag parameters containsInCell this.
                            row.set(i, parameters.get(v));

                            if (parameters.get(v).contains("null"))
                            {
                                System.err.println();
                            }

                        }
                    }
                }
            }

            // get the next componentTag
            x = d.poll();

            // toggle exit code if x is null, isn't a Tag, or it's a Tag, but it ends our highest object.
            if (x == null || !(x instanceof XTag) || ((x instanceof XTag) && (((XTag) x).getType().equals(containerType))))
            {
                inside = false;

                if ((x instanceof XTag) && (((XTag) x).getType().equals(containerType)))
                {
                    // if this was another model componentTag, it's either another model, or a closer.
                    // skip over it for the next look at things.
                    x = d.poll();
                }
            } else
            {

                t = importTag(x);

            }
        }


        if (!doc.isEmpty()) // assign components.
        {

            table.setComponents(getComponents(doc.copyOf(), paramValue, majorItemType, orderedLabels, refTable));
        }

        // put versions on the table

        table.setVersion(version);

        if (verColNum() > 0 && verColNum() < row.size())
        {
            for (int j = 1; j < table.size(); j++)
            {
                table.get(j).getValue().set(verColNum(), Tabler.abrevVersion(version));
            }
        }

        while (!d.isEmpty())
        {
            after.add(d.poll());
        }
        // put that collected info after the actual table.
        table.setInfoAfter(after);

        table.setDoc(doc);

        return table;
    }

    /**
     * imports a componentTag that is object x.
     * @param x - the XTag, as an object.
     * @return an XTag that represents x, once it has been processed for table
     * compatibility.
     */
    private XTag importTag(Object x)
    {
        if (x == null)
        {
            return null;
        }

        if (!(x instanceof XTag))
        {
            return null;
        }

        XTag t = ((XTag) x);
        String k, v;
        Entry ent;

        Iterator<Entry<String, String>> it = substitutes.entrySet().iterator();
        while (it.hasNext())
        {
            ent = it.next();

            k = (String) ent.getKey();
            v = (String) ent.getValue();

            // if the key doesn't exist, copy the componentTag's value for the key (which is the VALUE defined in this file).

            // example: if there is:
            // key: "name" value: "base" IN SUBSTITUTES
            // then check for the key "name" IN THE TAG'S PARAMETERS.
            if (!t.getParams().containsKey(k) && t.getParams().containsKey(v))
            {
                // if the key ("name") didn't exist IN TAG,
                // get the value for "name" IN SUBSITUTES ("base").
                // and get the value IN THE TAG, for that substituted key.
                // IN THE TAG, copy value for "base" to value for "name."
                t.getParams().put(k, t.getParams().get(v));
            }
        }

        return t;
    }

    /**
     * makes a table based on "component" tags, instead of the normal way.
     * this is for documents such as TR-143.
     * @param doc - the document to table.
     * @param model - the name of the model to parse out
     * @param majorItemType - the type that defines a row.
     * @param orderedLabels - the lables to use for row names, in order of priority.
     * @param refTable - the bibliographic information, in a table.
     * @return a table of the information parsed out.
     * @throws Exception - upon any error.
     */
    private ArrayList<TRComponent> getComponents(XDoc doc, String model, String majorItemType, String[] orderedLabels, XTable refTable) throws Exception
    {
        XTag componentTag = null, refTag = null, tempTag = null;
        ArrayList<TRComponent> components = new ArrayList<TRComponent>();
        TRComponent comp;
        Object o = null;
        XDoc tempDoc;
        ArrayList<XTag> refs;
        XTable otherTable, tableThree;
        IndexedHashMap<XTag, XDoc> docs = new IndexedHashMap<XTag, XDoc>();
        HashMap<String, String> descriptions = new HashMap<String, String>();
        Entry<XTag, XDoc> ent;
        String path;
        int j;
        String tmp;
        Row row;
        DescriptionHandler descrHandler = new DescriptionHandler();
        boolean b = false;

        if (doc.containsTagType("component"))
        {
            // find the model, create a list of addresses of components
            tempDoc = new XDoc(doc);
            refs = new ArrayList<XTag>();

            o = tempDoc.poll();

            while (!((o == null) || (o instanceof XTag && ((XTag) o).getParams().containsValue(model) && !((XTag) o).isCloser() && ((XTag) o).getType().equalsIgnoreCase("model"))))
            {
                o = tempDoc.poll();
            }

            o = tempDoc.poll();

            if (!doc.isEmpty())
            {
                while (!((o == null) || (o instanceof XTag && ((XTag) o).getParams().containsValue(model) && ((XTag) o).isCloser() && ((XTag) o).getType().equalsIgnoreCase("model"))))
                {
                    if (!((XTag) o).isCloser())
                    {
                        refs.add((XTag) o);
                    }

                    o = tempDoc.poll();
                }
            }

            // referenceNames is now an XDoc of the required component's ref tags.

            o = doc.poll();
            while (!((o == null) || (o instanceof XTag && !((XTag) o).isCloser() && ((XTag) o).getType().equalsIgnoreCase("component"))))
            {
                o = doc.poll();
            }

            if (!doc.isEmpty())
            {
                componentTag = (XTag) o;
            }

            // while there is a component
            while (componentTag != null)
            {
                // make use the attributes to make a string as to where it goes,
                // use ModelTable.SEPARATOR.

                refTag = null;
                for (int i = 0; i < refs.size() && refTag == null; i++)
                {
                    if (refs.get(i).getParams().get("ref").equalsIgnoreCase(componentTag.getParams().get("name")))
                    {
                        refTag = refs.get(i);
                    }
                }

                if (refTag != null)
                {
                    // make a doc out of the component.
                    tempDoc = new XDoc();
                    tempDoc.add(o);
                    o = doc.poll();

                    tempTag = importTag(o);

                    if (tempTag != null && descrHandler.getTypeHandled().equalsIgnoreCase(tempTag.getType()))
                    {
                        descriptions.put(refTag.getParams().get("ref"), descrHandler.handle(doc, tempTag, b));
                        o = doc.poll();
                    }

                    while (!((o == null) || (o instanceof XTag && ((XTag) o).isCloser() && ((XTag) o).getType().equalsIgnoreCase("component"))))
                    {
                        tempDoc.add(o);
                        o = doc.poll();
                    }

                    tempDoc.setVersion(doc.getVersion());

                    docs.put(refTag, tempDoc);
                }
                //find next component opener.

                o = doc.poll();
                while (o != null && !(o instanceof XTag && !((XTag) o).isCloser() && ((XTag) o).getType().equalsIgnoreCase("component")))
                {
                    o = doc.poll();
                }

                if (doc.isEmpty())
                {
                    componentTag = null;
                } else
                {
                    componentTag = (XTag) o;
                }

            }// end while
        }// end if

        // here we have all info needed.
        // make a list of components to return with the regular table.
        // then, when the table gets back to makewholetable, we'll do a special merge.

        for (int i = 0; i < docs.size(); i++)
        {
            ent = docs.get(i);
            path = ent.getKey().getParams().get("path");
            tempDoc = ent.getValue();
            tableThree = new XTable();

            otherTable = parseContainer(docs.get(i).getValue(), "name", docs.get(i).getKey().getParams().get("ref"), majorItemType, orderedLabels, refTable, false);

            for (int k = 0; k < otherTable.size(); k++)
            {


                tmp = otherTable.get(k).getKey();
                row = otherTable.get(k).getValue();


                if (row.get(typeColNum()).getData().equalsIgnoreCase("Object"))
                {
                    row.get(0).prePend(path);
                    row.get(verColNum()).set(Tabler.abrevVersion(model));
                }
                tmp = path + tmp;

                tableThree.put(tmp, row);
            }

            comp = new TRComponent(tableThree);
            comp.importParams(ent.getKey().getParams());

            comp.setDescription(descriptions.get(comp.getParams().get("ref")));

            components.add(comp);
        }

        return components;
    }

    @Override
    protected Table getComponents(Doc doc, String model) throws Exception
    {
        return this.getComponents((XDoc) doc, model);
    }

    @Override
    public XTable parseContainer(Doc d, String param, String paramValue, String MajorItemType, String[] orderedLabels, XTable refTable, boolean includeContainer) throws Exception
    {

        if (d instanceof XDoc)
        {
            return parseContainer((XDoc) d, param, paramValue, MajorItemType, orderedLabels, refTable, includeContainer);
        }

        throw new Exception("Wrong type of document for this Tabler");
    }

    @Override
    public boolean canParse(Doc d)
    {
        return (d instanceof XDoc);
    }

    private String getDMR(XTag t)
    {
        // TODO: update to somehow get as much of path as possible

        String dmr = null;

        dmr = t.getParams().get("dmr:previousParameter");

        if (dmr == null)
        {

            dmr = t.getParams().get("dmr:previousObject");
        }

        if (dmr == null)
        {
            dmr = t.getParams().get("dmr:previousProfile");
        }

        return dmr;
    }
}
