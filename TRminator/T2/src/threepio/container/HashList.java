/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */

package threepio.container;

import java.util.ArrayList;
import java.util.HashMap;

/**
 *
 * @author jhoule
 */
public class HashList<K,V> extends HashMap<K, ArrayList<V>> {

    public boolean put(K k, V v)
    {
        return this.get(k).add(v);
    }

}
