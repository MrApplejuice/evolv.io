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
  
  public SoftBodyShadow(SoftBody softBody) {
    body = softBody;
    update();
  }
  
  public void update() {
    lock.writeLock().lock();
    try {
      position.set(body.getPosition());
      radius = body.getRadius();
    }
    finally {
      lock.writeLock().unlock();
    }
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
  
  public int getId() {
    return body.getId();
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
    if (index > sortedShadows.size()) {
      // Execute handler
      final List<SoftBody> softBodies = new ArrayList<SoftBody>(sortedShadows.size());
      for (SoftBodyShadow shadow : sortedShadows) {
        softBodies.add(shadow.body);
      }
      handler.handleLockedSoftBodyArray(softBodies);
    } else {
      // Keep locking intrinsic locks
      synchronized (sortedShadows.get(index)) {
        recurseLocks(index + 1, sortedShadows, handler);
      }
    }
  }
  
  public static void lockListOfSoftBodies(List<SoftBodyShadow> shadows, LockedSoftBodyArrayHandler handler) {
    final List<SoftBodyShadow> sortedShadows = new ArrayList<SoftBodyShadow>(shadows);
    sortedShadows.sort(SoftBodyShadowIdComparator);
    recurseLocks(0, sortedShadows, handler);
  }
}