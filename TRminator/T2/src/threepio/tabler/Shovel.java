/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package threepio.tabler;

import java.util.Arrays;
import threepio.container.HashedLists;
import threepio.container.NamedLists;
import threepio.documenter.XDoc;
import threepio.documenter.XTag;

/**
 * A Shovel digs into a document (usually a snippet of a document) for
 * various items, and places Strings or other Java representations of them
 * in a HashedLists.
 *
 * @see ModelTabler
 * @author jhoule
 */
public abstract class Shovel {

    protected String digs[];

    /**
     * Fills the bucket with information based on the document passed.
     * @param bucket - the bucket to add to (may be non-empty, but shoudl be initialized)
     * @param doc - the document, which will be missing items from the original head to the end of processing.
     * @return the bucket, which may or may not have been added to, but was not modified in any other way.
     */
    public abstract NamedLists<Object> fill(NamedLists<Object> bucket, XDoc doc);

    public boolean canDig(XTag t)
    {
        return canDig(t.getType());
    }

    /**
     * Checks if the shovel processes the type of tag passed.
     * If this returns False,
     * @param type
     * @return
     */
    public boolean canDig(String type)
    {
    String[] temp = Arrays.copyOf(digs, digs.length);

    for (String s: temp)
    {
        s = s.toLowerCase();
    }


        return ((Arrays.binarySearch(temp, type.toLowerCase())) >= 0);
    }

}
