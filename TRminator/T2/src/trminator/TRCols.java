/*
 * File: TRCols.java
 * Project: TRminator
 * Author: Jeff Houle
 */
package trminator;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import threepio.container.Doublet;
import threepio.documenter.TagExtractor;
import threepio.documenter.XTag;
import threepio.engine.ColumnDescriptor;
import threepio.filehandling.FileIntake;
import threepio.tabler.container.ColumnMap;
import threepio.tabler.container.ModelTable;
import threepio.tagHandler.DescriptionHandler;
import threepio.tagHandler.HandlerFactory;
import threepio.tagHandler.NameHandler;
import threepio.tagHandler.SyntaxHandler;
import threepio.tagHandler.TagHandler;

/**
 * A class that constructs common ColumnDescriptor Objects for use in making
 * ModelTables.
 * @author jhoule
 * @see ModelTable
 * @see ColumnDescriptor
 */
public class TRCols
{

    /**
     * The ColumnDescriptor for the "write" parameter in BBF XML
     */
    public static class WriteCol extends ColumnDescriptor
    {

        public String getTypeHandled()
        {
            return "Write";
        }

        public String getFriendlyName()
        {
            return "access";
        }
    }

    /**
     * The ColumnDescriptor for the "default" parameter in BBF XML
     */
    public static class DefaultCol extends ColumnDescriptor
    {

        public String getTypeHandled()
        {
            return "default";
        }

        public String getFriendlyName()
        {
            return "Default";
        }
    }

    /**
     * The ColumnDescriptor for the "Version" parameter in BBF XML
     */
    public static class VersionCol extends ColumnDescriptor
    {

        public String getTypeHandled()
        {
            return "Version";
        }

        public String getFriendlyName()
        {
            return "version";
        }
    }

    /**
     * Constructs and returns the ColumnMap that is used by default
     * for BBF documents.
     * @return the newly created cols of columns.
     */
    public static ColumnMap getDefaultColMap()
    {
        ColumnMap map = new ColumnMap();

        NameHandler nh = new NameHandler();
        SyntaxHandler sh = new SyntaxHandler();
        DescriptionHandler dh = new DescriptionHandler();
        WriteCol wc = new WriteCol();
        DefaultCol dc = new DefaultCol();
        VersionCol vc = new VersionCol();

        map.put(nh.toColMapEntry());
        map.put(sh.toColMapEntry());
        map.put(wc.toColMapEntry());
        map.put(dh.toColMapEntry());
        map.put(dc.toColMapEntry());
        map.put(vc.toColMapEntry());

        return map;
    }

    /**
     * Creates a ColumnMap by looking at a special ColumnMap file.
     * The file format MUST be XML in the style:
     * <ColumnMap name="default">
     * <Column construct="false" title="Type" handles="type"/>
     * <Column construct="true" title="Write" handles="access"/>
     * <Column construct="false" title="Description" handles="description"/>
     * <Column construct="true" title="Default" handles="default"/>
     * <Column construct="true" title="Version" handles="version"/>
     * </ColumnMap>
     * @param f
     * @return
     * @throws Exception
     */
    public static ColumnMap loadFromFile(File f) throws Exception
    {
        XTag tmp;
        String name, title, handles, constructString;
        ColumnMap cols = new ColumnMap();
        HashMap<String, String> params;
        Boolean construct;
        HandlerFactory factory;
        TagHandler th;

        ArrayList<XTag> tags;

        f = FileIntake.resolveFile(f);

        String content = FileIntake.fileToString(f);

        if (content.trim().isEmpty())
        {
            throw new IllegalStateException("Attempting to load Cols from empty file.");
        }

        tags = TagExtractor.extractTags(content);

        // needs to be at least size 3.

        if (tags.size() < 3)
        {
            throw new IllegalStateException("incomplete column Map (lower than size 3)");
        }

        // first and last tag should be of type ColumnMap

        tmp = tags.get(0);

        if (!tmp.getType().equalsIgnoreCase("ColumnMap"))
        {
            throw new IllegalStateException("The first element is not a ColumnMap container");
        }

        name = tmp.getParams().get("name");
        cols.setName(name);


        tmp = tags.get(tags.size() - 1);

        if (tmp.getType().equalsIgnoreCase("ColumnMap"))
        {
            if (!tmp.isCloser())
            {
                throw new IllegalStateException("The last element does not close ColumnMap container");
            }
        } else
        {
            throw new IllegalStateException("The last element is not a ColumnMap container");
        }


        factory = new HandlerFactory();

        for (int i = 1; i < tags.size() - 1; i++)
        {
            tmp = tags.get(i);

            // construct a Column Entry based on the tag.

            // should be a Column tag that self closes.

            if (!tmp.isSelfCloser())
            {
                throw new IllegalStateException("A column tag does not self-terminate.");
            }

            params = tmp.getParams();
            constructString = params.get("construct");
            title = params.get("title");
            handles = params.get("handles");

            construct = Boolean.parseBoolean(constructString);

            if (construct)
            {
                cols.put(new Doublet<String, String>(title, handles));
            } else
            {
                th = factory.getHandler(handles);

                if (th == null)
                {
                    throw new IllegalArgumentException("the Tag Handler Factory " +
                            "does not have a handler for: " + handles +
                            ".\nPlease implement one or " +
                            "change the \"construct\" flag to TRUE\n" +
                            "in the columns XML file: " + f.getPath() );
                }
                cols.put(factory.getHandler(handles).toColMapEntry());
            }
        }

        return cols;
    }
}
