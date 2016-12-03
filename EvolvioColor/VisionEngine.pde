import java.awt.Color; 

/**
  Implements 2D vision system of a creature.  
 */
static class VisionSystem {
  public final static double MAX_VISION_DISTANCE = 10;

  private LinearAlgebraPool linAlgPool;
  
  private double[] visionAngles = {0, -0.4, 0.4};
  private double[] visionDistances = {0, 0.7, 0.7};
  
  private Vector2D[] visionEndpoints = new Vector2D[visionAngles.length];
  private Vector2D[] visionRangePoints = new Vector2D[visionAngles.length];
  
  private ArrayList<SoftBodyShadow> potentialVisionOccluders = new ArrayList<SoftBodyShadow>();
  
  private double[] visionValues = new double[visionAngles.length * 3];
  
  
  public VisionSystem(LinearAlgebraPool linAlgPool) {
    this.linAlgPool = linAlgPool;
    
    for (int i = 0; i < visionEndpoints.length; i++) {
      visionEndpoints[i] = new Vector2D(); // Unpooled, these are static anyway! 
      visionRangePoints[i] = new Vector2D(); // Unpooled, these are static anyway! 
    }
  }
  
  public void updateVision(AbstractBoardInterface board, Vector2D origin, double rotation, SoftBody ignore) {
    float[] hsbValues = new float[3];
    
    final Vector2D tmpV = linAlgPool.getVector2D();
    for (int k = 0; k < visionAngles.length; k++) {
      potentialVisionOccluders.clear();
      
      final double visionTotalAngle = rotation + visionAngles[k];

      visionRangePoints[k].set(visionDistances[k] * Math.cos(visionTotalAngle),
                             visionDistances[k] * Math.sin(visionTotalAngle));
      visionRangePoints[k].inplaceAdd(origin);

      color c = board.getTileColor(visionEndpoints[k]);
      // Cannot use the hue/saturation/brightness functions in a static class :-(
      Color.RGBtoHSB((c >> 16) & 0xFF, (c >> 8) & 0xFF, (c >> 0) & 0xFF, hsbValues);
      visionValues[k * 3] = hsbValues[0];
      visionValues[k * 3 + 1] = hsbValues[1];
      visionValues[k * 3 + 2] = hsbValues[2];
      
      // Iterative line propagation - perhaps use a default here like Bresenham's or Wu's line algorithm?
      Vector2D currentTile = null;
      Vector2D prevTile = null;
      for (int DAvision = 0; DAvision < visionDistances[k] + 1; DAvision++) {
        currentTile = linAlgPool.getVector2D().set((int) (origin.getX() + Math.cos(visionTotalAngle) * DAvision),
                                                   (int) (origin.getY() + Math.sin(visionTotalAngle) * DAvision));
        if (!currentTile.equals(prevTile)) {
          potentialVisionOccluders.addAll(board.getSoftBodyShadowsAtPosition(currentTile));
          if ((prevTile != null) && (prevTile.getX() != currentTile.getX()) && (prevTile.getY() != currentTile.getY())) {
            tmpV.set(prevTile.getX(), currentTile.getX());
            potentialVisionOccluders.addAll(board.getSoftBodyShadowsAtPosition(tmpV));
            tmpV.set(currentTile.getX(), prevTile.getX());
            potentialVisionOccluders.addAll(board.getSoftBodyShadowsAtPosition(tmpV));
          }
        }
        
        linAlgPool.recycle(prevTile);
        prevTile = currentTile;
        currentTile = null;
      }
      linAlgPool.recycle(prevTile);
      
      final Matrix2D unrotateMatrix = linAlgPool.getMatrix2D().setRotationMatrix(-visionTotalAngle);
      final Vector2D visionEndTip = linAlgPool.getVector2D().set(visionDistances[k], 0);
      
      
      for (SoftBodyShadow shadow : potentialVisionOccluders) {
        if ((ignore != null) && (shadow.getId() == ignore.getId())) {
          continue;
        }
        
        final Vector2D pos = linAlgPool.getVector2D().set(shadow.getPosition());
        pos.inplaceSub(origin);
        
        final double radius = shadow.getRadius();
        final Vector2D rotatedPos = unrotateMatrix.dotProduct(pos);
        
        if (Math.abs(rotatedPos.getY()) <= radius) { // Test: Sphere of the other body intersects with the vision beam
          if ((rotatedPos.getX() >= 0 && rotatedPos.getX() < visionEndTip.getX() && rotatedPos.getY() < visionEndTip.getX()) || // I get the X-checks: a rough check (ignoring the effective projected radius) on "falls withing vision range". I do not get the Y-part.   
            rotatedPos.length() < radius || // Is the vision origin within the collision sphere?
            visionEndTip.distance(rotatedPos) < radius) {  // Very crude check checking if the vision end point falls inside the collision sphere
            // YES! There is an occlussion.
            visionEndTip.set(rotatedPos.getX() - Math.sqrt(radius * radius - rotatedPos.getY() * rotatedPos.getY()), 0);

            visionValues[k * 3] = shadow.getHue();
            visionValues[k * 3 + 1] = shadow.getSaturation();
            visionValues[k * 3 + 2] = shadow.getBrightness();
          }
        }

        
        linAlgPool.recycle(pos);
        linAlgPool.recycle(rotatedPos);
      }
      
      // Save vision end position and colors
      visionEndpoints[k].set(visionEndTip.getX() * Math.cos(visionTotalAngle),
                             visionEndTip.getX() * Math.sin(visionTotalAngle));
      visionEndpoints[k].inplaceAdd(origin);
      
      linAlgPool.recycle(visionEndTip);
      linAlgPool.recycle(unrotateMatrix);
    }
    
    linAlgPool.recycle(tmpV);
  }

  public Vector2D[] getVisionEndpoints() {
    return visionEndpoints;
  }

  public Vector2D[] getVisionRangePoints() {
    return visionRangePoints;
  }

  public double[] getValues() {
    return visionValues;
  }
}