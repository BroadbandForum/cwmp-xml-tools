/*
 * File: XDocumenter.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import threepio.filehandling.FileIntake;
import java.io.File;
import java.io.FileNotFoundException;
import java.util.ArrayList;
import java.util.Map.Entry;

/**
 * XDocumenter imports an XML file to an XDoc.
 * This is done by reading the file for tags and the strings between them, and
 * putting them into the XDoc sequentially.
 * The end result of the conversion is a container.
 *
 * It's possible that this class and others used for XML conversion can also
 * be used for HTML conversion, but this is untested.
 *
 * @see XDoc
 * @author jhoule
 */
public class XDocumenter implements Documenter
{
    XDoc doc;
    StringBuffer buff;
    int e = 0;
    int s = 0;
    String temp = null;

    /**
     * Sets up the Documenter, using the input file supplied to the method.
     * @param f - the input file for the documentation process.
     */
    private void setUp(File f) throws Exception
    {
        doc = new XDoc();
        try
        {
            if (! FileIntake.canResolveFile(f))
            {
                throw new FileNotFoundException("cannot document the file. it is missing.");
            }

            buff = FileIntake.fileToStringBuffer(f, true);
        } catch (Exception ex)
        {
            throw (ex);
        }
        e = 0;
        s = 0;
        temp = null;

        doc.path = f.getPath();
    }

    @Override
    public XDoc convertFile(Entry<String, String> info) throws Exception
    {
        File inFile = FileIntake.resolveFile(new File(info.getValue()), true);
        
        if (inFile == null)
        {
            throw new FileNotFoundException("Documenter cannot convert the file. It doesn't exist.");
        }
        setUp(inFile);

        doc.setVersion(info.getKey());

        return theRest();
    }

    /**
     * converts the supplied XML or HTML file to an XDoc
     * @param f - the file
     * @return the document, as a bucket of tags and strings.
     * @throws Exception - when files are missing.
     */
    @Override
    public XDoc convertFile(File f) throws Exception
    {
        setUp(f);
        doc.setVersion(f.getName());
        return theRest();
    }

    /**
     * getTagsOfType gets a list of tags from a file that are the type passed.
     * @param f - the file to inspect.
     * @param type - the type of tag to get.
     * @return - a list of the tags.
     * @see java.util.ArrayList
     * @throws Exception - if anything goes awry on file intake.
     */
    public ArrayList<XTag> getTagsOfType(File f, String type) throws Exception
    {
        ArrayList<XTag> list = new ArrayList<XTag>();

        setUp(f);

        if (buff.lastIndexOf("</import>") > 0)
        {
            buff.delete(0, buff.lastIndexOf("</import>") + "</import>".length());
        }

        while (buff.lastIndexOf("<" + type) > 0)
        {

            s = (buff.indexOf("<" + type));
            s++;
            e = buff.indexOf("<", s);
            s--;

            list.add(new XTag(buff.substring(s, e)));
            buff.delete(0, e - 2);
        }

        return list;
    }

    /**
     * returns a list of all of the vals of models in the file
     * @param f - the file to look in.
     * @return -  a list of the models' vals.
     * @see java.util.ArrayList
     * @throws Exception - upon any error reading the file.
     */
    public ArrayList<String> getModelNames(File f) throws Exception
    {
        return getPropertyOfType(f, "name", "model");
    }

    /**
     * returns a list of the property specified of all the items of the type specified
     * as found in the file, f.
     * @param f - the file to look in.
     * @param property - the property to list.
     * @param type - the type of item to inspect.
     * @return the list of the property of the items of the type.
     * @throws Exception - when something goes awry with inspecting the file.
     */
    public ArrayList<String> getPropertyOfType(File f, String property, String type) throws Exception
    {
        ArrayList<XTag> tags = getTagsOfType(f, type);
        ArrayList<String> vals = new ArrayList<String>();

        for (int i = 0; i < tags.size(); i++)
        {
            vals.add(tags.get(i).getParams().get(property));
        }

        return vals;
    }

    /**
     * theRest is a common body for file documenting,
     * used by the varying convertFile methods.
     *
     * @return - the result of the documentation.
     * @throws Exception - if an error is found on input
     */
    private XDoc theRest() throws Exception
    {
        while (buff.length() > 0)
        {
            s = buff.indexOf("<");
            e = buff.indexOf(">");

            if (s == 0)
            {
                if (e < 1)
                {
                    throw new Exception("End tag ->- missing for this tag");
                }

                if (buff.substring(0, 1).matches("\\s"))
                {
                    System.err.println("Tag body starts with whitespace: ");
                    System.err.println(buff.substring(s, e + 1));
                    //throw new Exception("Tag body starts with whitespace");
                }

                if (buff.substring(e - 1, e).matches("\\s"))
                {
                    System.out.println("WARNING: Tag body ends with whitespace:");
                    System.out.println("\t" + buff.substring(s, e + 1));
                    System.out.println();
                    //throw new Exception("Tag body ends with whitespace");
                }

                XTag tempTag = new XTag(buff.substring(s, e + 1).trim());
                doc.add(tempTag);
                buff.delete(s, e + 1);
            } else
            {
                if (s < 0)
                {
                    // couldn't find another tag, so just use the end of the buffer as the place to stop.
                    s = buff.length();
                }

                temp = buff.substring(0, s).trim();

                if (temp.length() > 0)
                {
                    doc.add(temp);
                }

                // flush parsed stuff from buffer
                buff.delete(0, s);
            }
        }
        return doc;
    }
}
