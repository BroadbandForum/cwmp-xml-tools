/*
 * File: CIExclusiveStringList.java
 * Project: Threepio
 * Author: Jeff Houle
 */

package threepio.container;

import java.util.Collections;

/**
 * A Case-Insensitive String Array List
 * that is, searching for "foo" in one of these lists that contains "foo," "fOO,"
 * etc will result in a positive.
 * @author jhoule
 */
public class CIExclusiveStringList extends ExclusiveArrayList<String> {

    @Override
    public boolean contains(Object o)
    {
        if (o instanceof String)
        {
           Collections.sort (this, String.CASE_INSENSITIVE_ORDER);



           return (Collections.binarySearch(this, (String)o, String.CASE_INSENSITIVE_ORDER) >= 0);

        }

        return false;
    }



}
