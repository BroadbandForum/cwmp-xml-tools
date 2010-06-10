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
import java.util.regex.Matcher;
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
    private HashMap<String, String> attributes;
    /**
     * A CSV list of the artificially inserted attributes.
     * Keeps them from showing up when spitting tag back out.
     */
    private String artificial = "type,";

    /**
     * no-argument constructor.
     * sets up attributes as a new HashMap.
     */
    public XTag()
    {
        attributes = new HashMap<String, String>();
    }

    /**
     * Constructor, taking in raw text of a tag.
     * @param raw - the raw text of a tag
     * @throws Exception - when files are missing
     */
    public XTag(String raw) throws Exception
    {
        this();

        // check against formatting requirements.
        Matcher match = genericMatcher(raw);
        if (!match.matches())
        {
            throw new Exception("raw input does not match required tag format!");
        }

        /**
         * cursor for spaces
         */
        int space = -1;

        /**
         * cursor for right angle brackets (greater thans).
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

            

            // find the first space in the tag
            space = raw.indexOf(" ");

            // find where the tag ends.
            rbracket = raw.indexOf(">");

            if (raw.charAt(rbracket - 1) == '/')
            {
                selfCloser = true;
            }

            // if there are no spaces, there must just be a type.
            if (space < 0)
            {
                space = rbracket - 1;
            }
            type = type.substring(0, space).trim();

            // make sure tag ends with right angle bracket (greater than)
            if (rbracket < 0)
            {
                System.err.println("can't find a right bracket.");
                throw new Exception("Tag formating error.");
            }

            // get attributes. here, keys becomes both keys and values, separated
            toProcess = raw.substring(space, rbracket).split("=");

            // clean up the attributes, putting them on a list.
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
                attributes.put(key, value);
            }

            //add the artificial parameter type.
            attributes.put("type", type);
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
     * returns the map of attributes
     * @return the map
     */
    public HashMap<String, String> getAttributes()
    {
        return attributes;
    }

    /**
     * returns the string representation of this XTag.
     * attributes are NOT guaranteed to be in original order.
     * artificially created tags for other purposes are NOT included.
     * @return the Tag as a string.
     */
    @Override
    public String toString()
    {
        String k, v;
        StringBuffer buff = new StringBuffer();

        // open tag
        buff.append("<");

        if (isCloser())
        {
            buff.append('/');
        }

        buff.append(getType());

        // put attributes in
        Iterator<Entry<String, String>> it = attributes.entrySet().iterator();
        Entry<String, String> ent = null;

        // parse through attributes.
        while (it.hasNext())
        {
            ent = it.next();
            k = ent.getKey();

            // insert non-artificial params only.
            if (!(artificial.contains(k)))
            {
                v = ent.getValue();
                buff.append(" ");

                buff.append(k);
                buff.append("=\"");
                buff.append(v);
                buff.append("\"");
            }
        }

        // close tag

        if (isSelfCloser())
        {
            buff.append('/');
        }

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

    /**
     * constructs a String for a Pattern for matching tags of any type
     * @param canClose - if true, the tag can be a closing tag, otherwise it cannot.
     * @param caseSensitive - if true, CASE_INSENSITIVE option does not matter. If false, CASE_INSENSITIVE is needed to include lowercase tags.
     * @param allowWhiteSpaces - if true, will allow matches to tags with erroneous whitespace inside tag.
     * @return the string for the pattern.
     * @see Pattern#CASE_INSENSITIVE
     */
    public static String genericPatternString(boolean canClose, boolean allowWhiteSpaces, boolean caseSensitive)
    {
        StringBuffer buff = new StringBuffer();

        // start pattern of tag type
        buff.append("[");

        if (caseSensitive)
        {
            // account for case Sensitivity by adding the lowercase set of characters.
            // in truth, this subverts case sensitivity.
            buff.append("a-z");
        }

        // finish the tag type pattern
        buff.append("A-Z|\\?|\\!]+");

        return typedPatternString(canClose, allowWhiteSpaces, buff.toString());
    }

    /**
     * constructs a pattern that is used to match a type of tag.
     * @param canClose - if true, the tags found can contain the '/' prior to the type, in order to close an object.
     * @param allowWhiteSpaces - if true, will allow matches to tags with erroneous whitespace inside tag.
     * @param type - the type of tag to match.
     * @return a string representing the Pattern.
     */
    public static String typedPatternString(boolean canClose, boolean allowWhiteSpaces, String type)
    {
        StringBuffer buff = new StringBuffer();

        // open tag.
        buff.append("<");

        if (allowWhiteSpaces)
        {
            buff.append("\\s*");
        }

        if (canClose)
        {
            // make pattern accept tags that close objects.
            buff.append("/?");
        }

        // add tag type
        buff.append(type);

        // add the optional attributes pattern
        buff.append("[^>]*");

        if (allowWhiteSpaces)
        {
            buff.append("\\s*");
        }

        // close the tag
        buff.append(">");

        return buff.toString();
    }
    /**
     * Case-INSENSITIVE Pattern for a tag (cheap).
     */
    public static Pattern genericPattern = Pattern.compile(genericPatternString(true, true, false), Pattern.CASE_INSENSITIVE);

    /**
     * Case-INSENSITIVE Pattern for a type of tag (cheap).
     * @param type - the type of tag to match.
     * @return a Pattern for the type of tag.
     */
    public static Pattern typedPattern(String type)
    {
        return Pattern.compile(typedPatternString(true, true, type), Pattern.CASE_INSENSITIVE);
    }

    /**
     * Case-INSENSITIVE Pattern for a type of tag(cheap). Option to include closing tags or not.
     * @param type - the type of tag to match.
     * @param canClose - iff true, closing tags match, otherwise, they do not.
     * @return a Pattern for the type of tag.
     */
    public static Pattern typedPattern(String type, boolean canClose)
    {
        return Pattern.compile(typedPatternString(canClose, true, type), Pattern.CASE_INSENSITIVE);
    }

    /**
     * A matcher for the genericPattern 
     * @param str - the string to find matches in.
     * @return a Matcher for finding matches in the string.
     * @see #genericPattern
     */
    public static Matcher genericMatcher(String str)
    {
        return genericPattern.matcher(str);
    }

    /**
     * a Matcher for the typedPattern. Opiton to include closing tags or not.
     * @param str - the string to find matches in.
     * @param type - the type of tags to match.
     * @param canClose - iff true, closing tags match, otherwise they do not.
     * @return a Matcher for finding matches in the string.
     */
    public static Matcher typedMatcher(String str, String type, boolean canClose)
    {
        return typedPattern(type, canClose).matcher(str);
    }

    /**
     * a Matcher for typedPattern.
     * @param str - the string to find matches in.
     * @param type - the type of tags to match.
     * @return a matcher for finding matches in the string.
     */
    public static Matcher typedMatcher(String str, String type)
    {
        return typedPattern(type).matcher(str);
    }
}
