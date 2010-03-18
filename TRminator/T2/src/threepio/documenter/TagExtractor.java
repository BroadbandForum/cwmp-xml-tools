/*
 * File: TagExtractor.java
 * Project: Threepio
 * Author: Jeff Houle
 */
package threepio.documenter;

import java.util.ArrayList;
import java.util.List;
import threepio.helper.RegexHelper;

/**
 * TagExtractor extracts tags from a String, without modifying the String.
 * @author jhoule
 */
public class TagExtractor extends RegexHelper
{
    /**
     * extractTags (String) returns a list of XTag objects representing the tags
     * found in the String.
     * @param str - the String to list tags from.
     * @return the list of XTag objects.
     * @throws Exception - when making a tag fails.
     */
    public static ArrayList<XTag> extractTags(String str) throws Exception
    {
        return tagListFromStringList(extractAll(XTag.genericMatcher(str), str));
    }

    /**
     * extactTags (String, String) returns a list of XTag objects representing the tags found in the first String
     * which are of a "type" given as the Second String.
     * @param str - the String to list tags from.
     * @param type - the type of tag to list.
     * @return the list of XTag objectst of the desired type.
     * @throws Exception - when making a tag fails.
     */
    public static ArrayList<XTag> extractTypedTags(String str, String type) throws Exception
    {
        return extractTypedTags(str, type, true);
    }

    /**
     * extractTags (String, String, boolean) returns a list of XTag objects representing the tags found in the first String
     * which are of a "type" given as the second String. The boolean is a control for inclusion of "closing tags."
     * @param str - the String to list tags from.
     * @param type - the type of tag to list.s
     * @param includeClosers - if true, "closing" tags will be included in the list. Otherwise, they will not.
     * @return teh list of XTag objects of the desired type.
     * @throws Exception - when making a tag fails.
     */
    public static ArrayList<XTag> extractTypedTags(String str, String type, boolean includeClosers) throws Exception
    {
        return tagListFromStringList(extractAll(XTag.typedMatcher(str, type, includeClosers), str));
    }

    /**
     * tagListFromStringList is a helper function for tag extraction.
     * The list of Strings representing "tags," is returned as a list of XTag objects.
     * @param strs - the list of Strings to create XTag objects out of.
     * @return a list of XTag objects representing the items on the list of Strings.
     * @throws Exception - when an item on the String list cannot be turned into a XTag.
     */
    private static ArrayList<XTag> tagListFromStringList(List<String> strs) throws Exception
    {
        ArrayList<XTag> tags = new ArrayList<XTag>();
        for (String s : strs)
        {
            tags.add(new XTag(s));
        }

        return tags;
    }
}
