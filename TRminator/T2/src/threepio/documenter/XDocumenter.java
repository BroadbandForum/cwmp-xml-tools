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
import java.util.regex.Matcher;

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
    String fileContents;

    /**
     * Sets up the Documenter, using the input file supplied to the method.
     * @param f - the input file for the documentation process.
     * @throws Exception
     */
    private void setUp(File f) throws Exception
    {
        doc = new XDoc();
        try
        {
            if (!FileIntake.canResolveFile(f))
            {
                throw new FileNotFoundException("cannot document the file. it is missing.");
            }

            fileContents = FileIntake.fileToString(f, true);

        } catch (Exception ex)
        {
            throw (ex);
        }

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

        return theRest(fileContents);
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
        return theRest(fileContents);
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
        setUp(f);
        return TagExtractor.extractTypedTags(fileContents, type, false);
    }

    public ArrayList<String> getSecondaryModelNames(File f) throws Exception
    {
         setUp(f);
        int afterImp = 0;
        Matcher m = XTag.typedMatcher(fileContents, "import", true);

        String[] possibles = {"base", "ref"};
        ArrayList<String> names = new ArrayList<String>();

        while (m.find())
        {
            afterImp = m.end();
        }

        for (String s: possibles)
        {
            names.addAll(getPropertyOfType(fileContents.substring(afterImp), s, "model"));
        }

        return names;
    }

    /**
     * returns the top-level models' names, in a list of strings.
     * @param f - the file to search.
     * @return a list of the names (as strings) of the top-level models.
     * @throws Exception - when a tag analysis crashes.
     */
    public ArrayList<String> getMainModelNames(File f) throws Exception
    {
        setUp(f);
        int afterImp = 0;
        Matcher m = XTag.typedMatcher(fileContents, "import", true);

        String[] possibles = {"name"};
        ArrayList<String> names = new ArrayList<String>();

        while (m.find())
        {
            afterImp = m.end();
        }

        for (String s: possibles)
        {
            names.addAll(getPropertyOfType(fileContents.substring(afterImp), s, "model"));
        }

        return names;
    }

    /**
     * returns a list of all names of models in the file.
     * With this function, the models MAY be mentioned in IMPORT statements
     * or others.
     * @param f - the file to look in.
     * @return -  a list of the models' vals.
     * @see java.util.ArrayList
     * @throws Exception - upon any error reading the file.
     */
    public ArrayList<String> getAllModelNames(File f) throws Exception
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
     * returns a list of the property specified of all the imems of the type specified
     * in the string s.
     * @param s - the string that contains the tags to search.
     * @param property - the property of the specified tags to grab and list.
     * @param type - the type of tag to extract the property from.
     * @return a list (as strings) of the property specified of all tags of type.
     * @throws Exception
     */
    public ArrayList<String> getPropertyOfType(String s, String property, String type) throws Exception
    {
        ArrayList<XTag> tags = TagExtractor.extractTypedTags(s, type, false);
        ArrayList<String> vals = new ArrayList<String>();
        String tmp;

        for (int i = 0; i < tags.size(); i++)
        {
            tmp = tags.get(i).getParams().get(property);
            if (tmp != null)
            {
                vals.add(tmp);
            }
        }

        return vals;
    }

    /**
     * theRest is a common body for file documenting,
     * used by the varying convertFile methods.
     *
     * @param content - the contents of the file to work with.
     * @return - the result of the documentation.
     * @throws Exception - if an error is found on input
     */
    private XDoc theRest(String content) throws Exception
    {
        int s = 0;
        int e = 0;
        int next = 0;
        int len = content.length();
        String juice = "";

        // get the matcher for generic tags.
        Matcher matcher = XTag.genericMatcher(content);

        // find each tag
        while (matcher.find())
        {
            s = matcher.start();
            e = matcher.end();

            // check that there isn't text to capture before the tag.
            if (next >= 0 && next < s)
            {
                // try to make a string (without whitespaces) out of the space between the last tag and this one.
                juice = content.substring(next, s).trim();


                if (!juice.isEmpty())
                // there's some sort of string between the last tag and this one.
                {
                    doc.add(juice);
                }
            }

            // add this tag
            doc.add(new XTag(content.substring(s, e)));

            // point next at the character after the tag.
            next = e;

        }

        // there are no more tags... but check for a string after last tag.
        if (next < len)
        {
            doc.add(content.substring(next, len));
        }

        return doc;
    }
}
