

package threepio.tabler;

import threepio.container.HashedLists;
import threepio.container.Item;
import threepio.container.NamedLists;
import threepio.documenter.XDoc;
import threepio.documenter.XTag;

/**
 * A Shovel for the First Pass of Tabling a Document.
 *
 * It is intended to assist the Tabler during the First Pass in
 * gathering the information that gets
 * placed in the output during the Second Pass
 *
 * processed objects/parameters include:
 *      * "uniqueKey"
 *
 * @author jhoule
 */
public class FirstPassShovel extends Shovel{

    public FirstPassShovel()
    {
        super();

        digs = new String[1];
        digs[0] = "uniqueKey";

        
    }

    @Override
    public NamedLists<Object> fill(NamedLists<Object> bucket, XDoc doc)
    {
        XTag tag;

        if (! (doc.peek() instanceof XTag))
        {
            throw new IllegalArgumentException("document for First Pass Shovel did not begin with tag.");
        }

        tag = (XTag) doc.poll();

        if (tag.getType().equalsIgnoreCase("uniqueKey"))
        {
            bucket = grabKeys(bucket, doc);
        }

        return bucket;

    }

    private NamedLists<Object> grabKeys(NamedLists<Object> bucket, XDoc doc)
    {
        Object o;
        XTag t;
        Item item;
        String str;

        o = doc.peek();

        if (o instanceof XTag && ((XTag)o).getType().equals("uniqueKey"))
        {
            t = (XTag) doc.poll();
            item = new Item();

            o = t.getAttributes().get("functional");
            if(o != null)
            {
                item.getParams().set("functional", Boolean.parseBoolean((String) o));
            }

            // next item should be a tag, which is a parameter with a "ref" equal to the name of the key.

            o = doc.poll();

            if (o instanceof XTag && ((XTag)o).getType().equals("parameter"))
            {
                t = (XTag) doc.poll();

                str = t.getAttributes().get("ref");

                if (str == null)
                {
                    throw new IllegalArgumentException("an unnamed parameter is referenced as a uniqueKey.");
                }

                item.setLabel(str);

                bucket.putOnList("uniqueKeys", item);
            }
        }

        o = doc.poll();

        while (!(o instanceof XTag && ((XTag)o).getType().equals("uniqueKey")))
        {
            o = doc.poll();
        }

        return bucket;
    }

}
