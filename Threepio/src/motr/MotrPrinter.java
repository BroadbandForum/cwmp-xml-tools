/*
 * File: MotrPrinter.java
 * Project: moTR
 * Author: Jeff Houle
 */
package motr;

import threepio.printer.container.LinkedLevels;
import java.util.Iterator;
import java.util.Map.Entry;
import threepio.printer.FilePrinter;
import threepio.helper.XHTMLHelper;
import threepio.tabler.Path;
import threepio.tabler.container.Row;
import threepio.tabler.container.XTable;

/**
 *
 * @author jhoule
 */
public class MotrPrinter extends FilePrinter
{

    
    private static final String paramLevelIdentifier = "_params",
            parameterOpenTag = "<parameter>", parameterCloseTag = "</parameter>",
            parametersLevelOpenTag = "<parameters>", parametersLevelCloseTag = "</parameters>",
            nameOpenTag = "<parameterName>", nameCloseTag = "</parameterName>",
            typeOpenTag = "<parameterType>", typeCloseTag = "</parameterType>",
            lengthOpenTag = "<parameterLength>", lengthCloseTag = "</parameterLength>",
            arrayOpenTag = "<array>", arrayCloseTag = "</array>";

    @Override
    public String convertTable(XTable table, boolean diffMode, boolean looks) throws Exception
    {
        LinkedLevels<String> levels;
        Iterator<Entry<String, Row>> iterator = table.iterator();
        String pathString, name, type, wanted;
        Path path, lastPath = new Path(), otherPath;
        Row row;
        Entry<String, Row> ent;
        int colType = 1, compare;
        StringBuffer buffOut;

        // IMPORTANT: used to ID levels that are "parameters" levels.
        // example: if an item Foo.Bar has variables thing1 and thing2,
        // thing1 and thing2 will be in a level called "Bar_Params" inside a
        // level "Bar" inside a level "Foo_Params" inside a level "Foo."
        // this is mostly done for ease of printing.

        // check for initial contents of Table
        if (iterator.hasNext())
        {
            ent = iterator.next();
        } else
        {
            ent = null;
        }

        // check for header, and skip it if it is there.
        if (ent != null)
        {
            if (ent.getKey().contains("HEAD") && iterator.hasNext())
            {
                ent = iterator.next();
            } else
            {
                ent = null;
            }
        }

        // set up a new Linked Levels, to store the info.
        levels = new LinkedLevels<String>();

        // go through whole table, extracting info and inserting into Linked Levels object.
        while (ent != null)
        {
            // construct a Path object from the real path of the item.
            pathString = ent.getKey();
            path = new Path(pathString);

            // use the path to get the name of the item.
            name = path.getLastPart();
            // put it into desired format (in a tag)
            name = parseName(name);

            // use the row to get the type of the item.
            // this will be put in a tag LATER.
            row = ent.getValue();
            type = row.get(colType).toString();

            // find out how different this path is from the one before it.
            compare = path.compareTo(lastPath);

            switch (compare)
            {
                case -1:
                {
                    // there isn't a level of parameters under the current level.
                    levels.out();
                    break;
                }

                case 0:
                {
                    // this is the same item as the one before it?
                    throw new IllegalArgumentException("the same item apppared twice.");
                }

                default:
                {
                    if (compare < -1)
                    {
                        // need to go back to another "parameters" level.
                        // it is the level under the parameter that is 1 from the right
                        // in the path.

                        otherPath = path.removeI().removeLast();
                        wanted = otherPath.getLastPart();
                        wanted = wanted + paramLevelIdentifier;

                        // wanted is name of the parent item's "parameters" level.
                        while (!levels.getID().equals(wanted))
                        {
                            // get to that level.
                            levels.out();
                        }

                    } else if (compare > 0)
                    {
                        // need to create a new "parameters" level
                        if (compare > 1)
                        {
                            throw new IllegalArgumentException("Encountered a variable that is more than 1 path level ahead of previous one.");
                        }

                        try
                        {
                            levels.in();
                        } catch (Exception ex)
                        {
                            throw ex;
                        }
                        levels.setLabel(parametersLevelOpenTag);
                        levels.setTrailer(parametersLevelCloseTag);

                        levels.setID(lastPath.getLastPart() + paramLevelIdentifier);
                    }

                    break;
                } // end of default case
            } // end of swich on compare


            // create a level for the parameter
            levels.in();
            // give it the right tags.
            levels.setLabel(
                    parameterOpenTag);
            levels.setTrailer(
                    parameterCloseTag);

            // give it the name of this parameter. (good for debugging)
            levels.setID(path.getLastPart());

            // note that parseType will generate parameterLength line.
            // it will also indent any extra info it makes, based on the depth
            // passed it.
            type = parseType(type, path, levels.getDepth());

            // add the lines of text for this level.
            // most indentation (tabs) will be handled by levels object.
            levels.add(name);
            levels.add(type);

            // keep track of this path for comparison to next path.
            lastPath = path;

            // get next item
            if (iterator.hasNext())
            {
                ent = iterator.next();
            } else
            {
                ent = null;
            }
        }

        buffOut = new StringBuffer();

        //buffOut.append(prefix);

        // levels does a recursive toString on all levels, creating an "XML style"
        // string that is indented with a tab for each level.
        buffOut.append(levels.toString().trim());

        //buffOut.append(ending);

        return buffOut.toString();
    }

    private String parseName(
            String n)
    {
        return (nameOpenTag + n + nameCloseTag);
    }

    private String parseType(String t, Path p, int depth)
    {
        String state, main, tabs = XHTMLHelper.tabber(depth + 1);
        if (t.contains("("))
        {
            // is a String, with value in parens
            return parseType(t, '(', depth - 1);
        }

        // because motive stuff doesn't support list or datatype.
        t = t.replace("list", "string").replace("dataType", "string");


        main =
                typeOpenTag + t + typeCloseTag;

        if (t.equalsIgnoreCase("object"))
        {
            if (p.isArray())
            {
                state = "true";
            } else
            {
                state = "false";
            }

            return (main + "\n" + tabs + arrayOpenTag + state + arrayCloseTag);
        }

        return main;
    }

    private String parseType(String t, char start, int indents)
    {
        int where, close = -1, val = -1;
        String strInt;

        String regular;

        where =
                t.indexOf(start);

        regular =
                t.substring(0, where);
        regular =
                typeOpenTag + regular + typeCloseTag;

        switch (start)
        {
            case '(':
            {
                close = t.indexOf(')');
            }

        }

        if (close < 0)
        {
            throw new IllegalArgumentException(error(start));
        }

        switch (start)
        {
            case '(':
            {
                strInt = t.substring(where + 1, close);

                try
                {
                    val = Integer.parseInt(strInt);
                } catch (Exception ex)
                {
                    return regular;
                }

                return regular + "\n\t" + XHTMLHelper.tabber(indents) + "\t" + lengthOpenTag + val + lengthCloseTag;

            }

            default:
            {
                return regular;
            }

        }
    }

    private String error(char mode)
    {
        switch (mode)
        {
            case '(':
            {
                return "String size is missing closing parentheses";

            }

            case '[':
            {
                return "Int range is missing closing bracket";

            }

            default:
            {
                throw new IllegalArgumentException("bad mode");
            }
        }
    }

}
