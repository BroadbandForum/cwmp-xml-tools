/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package threepio.container;

import java.util.ArrayList;

/**
 *
 * @param <K>
 * @author jhoule
 */
public class Bucket<K> extends HashList<K, Object> {

    @SuppressWarnings("unchecked")
    public ArrayList putList(K k, ArrayList list)
    {
        return super.put(k,  list);
    }

}
