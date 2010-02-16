/*
 * File: XTag.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.Map.Entry;
import java.util.regex.Pattern;

/**
 * A self-building class for a Tag from XML or HTML.
 * Supply the raw text of the tag to the constructor, and properties are parsed out
 * and put into a hashmap.
 *
 * @author jhoule
 */
public class XTag
{
    /**
     * signifys if it's a closing tag or not.
     */
    private boolean closer;

    /**
     * signifies if it's a one-line, "self-terminating" tag or not.
     */
    private boolean selfCloser;

    /**
     * the type (first word) of the tag
     */
    private String type;
    /**
     * The rest of the contents of the strings, separated into keys and values,
     * entered into a HashMap.
     */
    private HashMap<String, String> parameters;

    /**
     * no-argument constructor.
     * sets up parameters as a new HashMap.
     */
    public XTag()
    {
        parameters = new HashMap<String, String>();
    }

    /**
     * Constructor, taking in raw text of a tag.
     * @param raw - the raw text of a tag
     * @throws Exception - when files are missing
     */
    public XTag(String raw) throws Exception
    {
        this();

        /**
         * placekeeper for spaces
         */
        int space = -1;

        /**
         * placekeeper for right angle brackets (greater thans).
         */
        int rbracket = -1;

        /**
         * temporary storage for parameter parsing.
         */
        ArrayList<String> cleanedKeysAndValues = new ArrayList<String>();
        String[] toProcess, processed;
        String temp, key, value;

        // skip over the first bracket (less than)
        type = raw.substring(1);

        // check if it is an end tag.
        if (type.startsWith("/"))
        {
            closer = true;

            // iff the tag is a closer, it should only contain a type.
            type = type.substring(1, raw.indexOf(">") - 1).trim();
        } else
        {
            closer = false;

            if (type.endsWith("/"))
            {
                selfCloser = true;
            }

            // find the first space in the tag
            space = raw.indexOf(" ");

            // find where the tag ends.
            rbracket = raw.indexOf(">");

            // if there are no spaces, there must just be a type.
            if (space < 0)
            {
                space = rbracket - 1;
            }
            type = type.substring(0, space).trim();

            // make sure tag ends with right angle bracket (greater than)
            if (rbracket < 0)
            {
                System.err.println("can't find a right bracket... was there no space?");
                throw new Exception("File format error.");
            }

            // get parameters. here, keys becomes both keys and values, separated
            toProcess = raw.substring(space, rbracket).split("=");

            // clean up the parameters, putting them on a list.
            // ends up that if a key is at i, it's value is at i+1.
            for (int j = 0; j < toProcess.length; j++)
            {
                processed = toProcess[j].trim().split(" ");

                for (int k = 0; k < processed.length; k++)
                {
                    temp = processed[k];
                    // strip quotes
                    temp = strippedString(temp, "\"");

                    // strip slashes
                    temp = strippedString(temp, "/");

                    cleanedKeysAndValues.add(temp);
                }
            }

            int s = cleanedKeysAndValues.size();

            // map items from list
            for (int i = 0; i + 1 < s && i < s; i += 2)
            {
                key = cleanedKeysAndValues.get(i);
                value = cleanedKeysAndValues.get(i + 1);
                parameters.put(key, value);
            }

 
            parameters.put("type", type);
        }
    }

    /**
     * Returns true if the tag is just intended to close item
     * @return true if the tag closes an item, false if it does not.
     */
    public boolean isCloser()
    {
        return closer;
    }

    /**
     * returns true if the tag is a one-line tag that terminates itself
     * @return true if the tag terminates itself, false if it does not.
     */
    public boolean isSelfCloser()
    {
        return selfCloser;
    }

    /**
     * Returns the type of object described by this XTag.
     * @return the type.
     */
    public String getType()
    {
        return type;
    }

    /**
     * returns the map of parameters
     * @return the map
     */
    public HashMap<String, String> getParams()
    {
        return parameters;
    }

    /**
     * returns the string representation of this XTag.
     * parameters are NOT guaranteed to be in original order.
     * @return the Tag as a string.
     */
    @Override
    public String toString()
    {
        StringBuffer buff = new StringBuffer();

        // open tag
        buff.append("<");
        buff.append(getType());

        // put parameters in 
        Iterator<Entry<String, String>> it = (Iterator<Entry<String, String>>) parameters.entrySet().iterator();
        Entry<String, String> ent = null;

        // parse through parameters.
        while (it.hasNext())
        {
            ent = it.next();
            buff.append(" ");

            buff.append(ent.getKey());
            buff.append("=\"");
            buff.append(ent.getValue());
            buff.append("\"");
        }

        // close tag
        buff.append(">");

        return buff.toString();
    }

    /**
     * Strips a string of another string.
     * 
     * @param str - the original string
     * @param what - what to strip from the string
     * @return the string with the parts removed.
     */
    private String strippedString(String str, String what)
    {
        int w;
        String ret = str;

        while (ret.contains(what))
        {
            w = ret.indexOf(what);

            ret = ret.substring(0, w) + ret.substring(w + 1, ret.length());
        }

        return ret;
    }

    public static String patternString = "</?[a-zA-z]*[^>]*>";
    public static Pattern pattern = Pattern.compile("</?[a-zA-z]*[^>]*>", Pattern.CASE_INSENSITIVE);
}
