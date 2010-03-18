/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package trminator;

import threepio.engine.ColumnDescriptor;
import threepio.tabler.container.ColumnMap;
import threepio.tagHandler.DescriptionHandler;
import threepio.tagHandler.NameHandler;
import threepio.tagHandler.SyntaxHandler;

/**
 *
 * @author jhoule
 */
public class TRCols
{

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
}
