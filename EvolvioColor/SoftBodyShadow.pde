import java.util.Comparator;
import java.util.concurrent.locks.ReentrantReadWriteLock;

/**
  For calculating relative locations to other entities in evlolvio it is not necessary
  to carry around all parameters of a soft body. The only interesting set is:
  
   - position
   - radius
  
  A shadow saves the state of the last frame of a SoftBody. Additionally, a SoftBodyShadow
  can be used to acquire a lock on the references soft body. 
  
  The SoftBodyShadow is designed to be thread-safe.
 */
public static class SoftBodyShadow {
  public static interface LockedSoftBodyArrayHandler {
    public void handleLockedSoftBodyArray(List<SoftBody> locked);
  };
  
  public static final Comparator<SoftBodyShadow> SoftBodyShadowIdComparator = new Comparator<SoftBodyShadow>() {
    public int compare(SoftBodyShadow b1, SoftBodyShadow b2) {
      return b1.getId() - b2.getId();
    }
  };
  
  private ReentrantReadWriteLock lock = new ReentrantReadWriteLock();
  
  private SoftBody body; 
  
  private Vector2D position = new Vector2D();
  private double radius = 0;
  private double hue = 0, saturation = 0, brightness = 0;
  
  public SoftBodyShadow(SoftBody softBody) {
    body = softBody;
    update();
  }
  
  public void update() {
    lock.writeLock().lock();
    try {
      position.set(body.getPosition());
      radius = body.getRadius();
      hue = body.getHue();
      saturation = body.getSaturation();
      brightness = body.getBrightness();
    }
    finally {
      lock.writeLock().unlock();
    }
  }
  
  public int getId() {
    return body.getId();
  }
  
  public Vector2D getPosition() {
    return getPosition(new Vector2D());
  }
  
  public Vector2D getPosition(Vector2D pos) {
    lock.readLock().lock();
    try {
      pos.set(position);
    }
    finally {
      lock.readLock().unlock();
    }
    return pos;
  }

  public double getRadius() {
    lock.readLock().lock();
    try {
      return radius; 
    }
    finally {
      lock.readLock().unlock();
    }
  }
  
  public double getHue() {
    return hue;
  }

  public double getSaturation() {
    return saturation;
  }

  public double getBrightness() {
    return brightness;
  }
  
  public Class getBodyClass() {
    return body.getClass();
  }
  
  public void handleLockedSoftBody(LockedSoftBodyArrayHandler handler) {
    final List<SoftBody> list = new ArrayList<SoftBody>(1);
    list.add(body);
    synchronized(body) {
      handler.handleLockedSoftBodyArray(list);
    }
  }
  
  private static void recurseLocks(int index, List<SoftBodyShadow> sortedShadows, LockedSoftBodyArrayHandler handler) {
    if (index < sortedShadows.size()) {
      // Keep locking intrinsic locks
      final SoftBodyShadow shadow = sortedShadows.get(index); 
      synchronized (shadow) {
        recurseLocks(index + 1, sortedShadows, handler);
      }
    } else {
      // Execute handler
      final List<SoftBody> softBodies = new ArrayList<SoftBody>(sortedShadows.size());
      for (SoftBodyShadow shadow : sortedShadows) {
        softBodies.add(shadow.body);
      }
      try {
        handler.handleLockedSoftBodyArray(softBodies);
      }
      catch (Exception e) {
        // This is only here, because Processing does not render these errors correctly!
        System.out.println("Intercepted error in SoftBodyShadow.recurseLocks: " + e.getMessage());
        e.printStackTrace();
      }
    }
  }
  
  public static void lockListOfSoftBodies(List<SoftBodyShadow> shadows, LockedSoftBodyArrayHandler handler) {
    final List<SoftBodyShadow> sortedShadows = new ArrayList<SoftBodyShadow>(shadows);
    sortedShadows.sort(SoftBodyShadowIdComparator);
    recurseLocks(0, sortedShadows, handler);
  }
}