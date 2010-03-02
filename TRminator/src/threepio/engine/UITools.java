/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package threepio.engine;

import threepio.tabler.container.IndexedHashMap;
import threepio.tagHandler.DescriptionHandler;
import threepio.tagHandler.NameHandler;
import threepio.tagHandler.SyntaxHandler;

/**
 *
 * @author jhoule
 */
public class UITools
{

    /**
     * setupCols fills the passed IndexedHashMap with the default values for columns, after emptying it.
     * @param cols - the IHM to fill up.
     */
    public static void setupCols(IndexedHashMap<String, String> cols)
    {
        cols.clear();

        // put entries IN ORDER for columns here.
        // first string is friendly name, second is hard-coded name.
        // hard-coded name is IMPORTANT to have EXACT.

        // TODO: find a way to keep ALL of this from being hand-written,
        // instead of only handlers that are currently listed.

        NameHandler nh = new NameHandler();
        SyntaxHandler sh = new SyntaxHandler();
        DescriptionHandler dh = new DescriptionHandler();

        // Name -> name
        cols.put(nh.getFriendlyName(), nh.getTypeHandled());
        // Type -> type
        cols.put(sh.getFriendlyName(), sh.getTypeHandled());

        cols.put("Write", "access");

        // Description -> description
        cols.put(dh.getFriendlyName(), dh.getTypeHandled());

        cols.put("Default", "default");
        cols.put("Version", "version");
    }
}
