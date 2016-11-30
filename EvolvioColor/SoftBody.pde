/**
  Extra traits for an object that has a rotation. 
 */
static interface OrientedBody {
  // Returns the rotation of the object in radians.
  public double getRotation();
};

/**
  Restriction: Soft bodies should be designed thread-safe! 
 */
class SoftBody {
  protected LinearAlgebraPool softBodyLinAlgPool = new LinearAlgebraPool();
  
  private int id;
  
  protected AbstractBoardInterface board;

  protected Vector2D position = new Vector2D();
  protected Vector2D velocity = new Vector2D();
  
  protected double energy;
  
  float ENERGY_DENSITY; // Set so when a creature is of minimum size, it equals one.
  double density;
  double hue;
  double saturation;
  double brightness;
  double birthTime;
  final float FRICTION = 0.004;
  final float COLLISION_FORCE = 0.01;
  final float FIGHT_RANGE = 2.0;

  public SoftBody(int id, Vector2D pos, Vector2D vel, double tenergy, double tdensity, 
    double thue, double tsaturation, double tbrightness, AbstractBoardInterface board, double bt) {
    
    this.id = id;
    position.set(pos);
    velocity.set(vel);
    this.board = board;
    
    energy = tenergy;
    density = tdensity;
    hue = thue;
    saturation = tsaturation;
    brightness = tbrightness;
    birthTime = bt;
    ENERGY_DENSITY = 1.0 / (Board.MINIMUM_SURVIVABLE_SIZE * Board.MINIMUM_SURVIVABLE_SIZE * PI);
  }

  public Vector2D getPosition() {
    return position;
  }

  public int getId() {
    return id;
  }
  
  public int xBound(int x) {
    return Math.min(Math.max(x, 0), board.getBoardWidth() - 1);
  }

  public int yBound(int y) {
    return Math.min(Math.max(y, 0), board.getBoardHeight() - 1);
  }

  public double xBodyBound(double x) {
    double radius = getRadius();
    return Math.min(Math.max(x, radius), board.getBoardWidth() - radius);
  }

  public double yBodyBound(double y) {
    double radius = getRadius();
    return Math.min(Math.max(y, radius), board.getBoardHeight() - radius);
  }

  public void collide(double timeStep, List<SoftBody> colliders) {
    for (final SoftBody collider : colliders) {
      double distance = position.distance(collider.getPosition());
      double combinedRadius = getRadius() + collider.getRadius();
      if (distance < combinedRadius) {
        double force = combinedRadius * COLLISION_FORCE;
        velocity.set(position).inplaceSub(collider.getPosition()).inplaceMul(force / distance / getMass());
      }
    }
  }

  public void applyMotions(double timeStep) {
    final Vector2D movement = softBodyLinAlgPool.getVector2D();
    movement.set(velocity).inplaceMul(timeStep);
    position.inplaceAdd(movement);
    velocity.inplaceMul(Math.max(0, 1 - FRICTION / getMass()));
    softBodyLinAlgPool.recycle(movement);
  }

  public void drawSoftBody(DrawConfiguration drawConfig, boolean isSelected, float scaleUp, float camZoom, boolean showVision) {
    double radius = getRadius();
    stroke(0);
    strokeWeight(drawConfig.getStrokeWeight());
    fill((float)hue, (float)saturation, (float)brightness);
    ellipseMode(RADIUS);
    ellipse((float)(position.getX() * scaleUp), (float)(position.getY() * scaleUp), (float)(radius * scaleUp), (float)(radius * scaleUp));
  }

  public double getRadius() {
    if (energy <= 0) {
      return 0;
    } else {
      return Math.sqrt(energy / ENERGY_DENSITY / Math.PI);
    }
  }

  public double getMass() {
    return energy / ENERGY_DENSITY * density;
  }
  
  /**
    This is a specialized function that copies the state of the current object into an internally 
    referenced static clone. This is done to copy the state so that all soft bodies can be updated 
    independently from each other - finally! 
   */
  private SoftBody theClone = null;
  public SoftBody getUpdatedStaticClone() {
   if (theClone == null) {
      theClone = new SoftBody(id, position, velocity, energy, density, hue, saturation, brightness, board, birthTime);
    } else {
      updateStaticCloneSoftBody(theClone);
    }
    return theClone;
  }
  
  protected void updateStaticCloneSoftBody(SoftBody theClone) {
    theClone.position.set(position);
    theClone.velocity.set(velocity);
    theClone.energy = energy;
    theClone.density = density; 
    theClone.hue = hue; 
    theClone.saturation = saturation; 
    theClone.brightness = brightness; 
    theClone.ENERGY_DENSITY = ENERGY_DENSITY;
  }
}