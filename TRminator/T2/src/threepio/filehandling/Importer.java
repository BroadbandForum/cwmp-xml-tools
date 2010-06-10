/*
 * File: Importer.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.filehandling;

import threepio.documenter.XDoc;
import threepio.documenter.XTag;
import java.util.ArrayList;
import java.util.HashMap;

/**
 * Importer locates and lists files required to make tables for data models.
 * @author jhoule
 */
public class Importer
{
    private HashMap<String, String> toTable, available;
    String biblio;

    /**
     * no-argument constructor
     */
    public Importer()
    {

        available = new HashMap<String, String>();
        toTable = new HashMap<String, String>();
        biblio = null;
    }

    /**
     * returns the map of stuff to table
     * @return the map.
     */
    public HashMap<String, String> getToTable()
    {
        return toTable;
    }

    /**
     * returns the presence of bibliographic information
     * @return true if the bibliographic info is attached, false if none is present.
     */
    public boolean hasBiblio()
    {
        return (biblio != null);
    }

    /**
     * returns the bibliographic information as a table.
     * @return the biblio table
     */
    public String getBiblio()
    {
        return biblio;
    }

    /**
     * does the main importing,
     * @param toImport - the doc to import
     * @param modelName - the name of the model to import.
     * @throws Exception - when there's a null or empty document or name
     */
    public void importFrom(XDoc toImport, String modelName) throws Exception
    {
        if (toImport == null || toImport.isEmpty())
        {
            throw new Exception("can't import from nothing");
        }

        if (modelName == null || modelName.isEmpty())
        {
            throw new Exception("no model specified!");
        }

        Object x;
        XTag imTag, modelTag, temp;
        String fName = null;
        ArrayList<String> basesNeeded = new ArrayList<String>();
        String nameFound;
        boolean go;

        XDoc doc = toImport.copyOf().purgeToTag("import");

        x = doc.peek();

        while (x instanceof XTag && ((XTag) x).getType().equalsIgnoreCase("import"))
        {
            imTag = (XTag) x;

            if (imTag.isCloser())
            {
                // skip </import> tags.
                doc.poll();
                x = doc.peek();
            } else
            {
                fName = imTag.getAttributes().get("file");
                if (fName.contains("biblio"))
                {
                    biblio = fName;
                }
               
                doc.poll();
                x = doc.peek();

                while (x instanceof XTag && !((XTag) x).isCloser() && !((XTag) x).getType().equalsIgnoreCase("import"))
                {
                    if (((XTag) x).getType().equalsIgnoreCase("model"))
                    {
                        modelTag = (XTag) x;

                        nameFound = modelTag.getAttributes().get("name");

                        // put an entry on the map, so that it can be
                        // processed as well.
                        available.put(nameFound, fName);
                    }

                    doc.poll();
                    x = doc.peek();
                }
            }
        }

        if (x == null)
        {
            doc = toImport.copyOf().purgeToTag("model");
            x = doc.peek();
        }
        
        go = true;
        while (go && (x != null))
        {
            if (x instanceof XTag)
            {
                temp = (XTag) x;

                if (temp.getType().equalsIgnoreCase("model") && temp.getAttributes().containsKey("name") && temp.getAttributes().get("name").equalsIgnoreCase(modelName))
                {
                    go = false;
                    break;
                }
            }

            doc.poll();
            x = doc.peek();
        }

        if (x == null || !(x instanceof XTag))
        {
            modelTag = null;
            throw new Exception("Model " + modelName + " not found!");

        } else
        {
            modelTag = ((XTag) x);
            if (modelTag.getAttributes().containsKey("base"))
            {
                basesNeeded.add(modelTag.getAttributes().get("base"));
            }
        }

        for (int i = 0; i < basesNeeded.size(); i++)
        {
            toTable.put(basesNeeded.get(i), available.get(basesNeeded.get(i)));
        }
    }
}


