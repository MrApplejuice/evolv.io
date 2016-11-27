/**
  Implements 2D vision system of a creature.  
 */
static class VisionSystem {
  public final double MAX_VISION_DISTANCE = 10;
  
  double[] visionAngles = {0, -0.4, 0.4};
  double[] visionDistances = {0, 0.7, 0.7};
  //double visionAngle;
  //double visionDistance;
  double[] visionOccludedX = new double[visionAngles.length];
  double[] visionOccludedY = new double[visionAngles.length];
  
  private double[] visionValues;
  
  private double getVisionEndX(int i) {
    double visionTotalAngle = rotation + visionAngles[i];
    return px + visionDistances[i] * Math.cos(visionTotalAngle);
  }

  private double getVisionEndY(int i) {
    double visionTotalAngle = rotation + visionAngles[i];
    return py + visionDistances[i] * Math.sin(visionTotalAngle);
  }
  
  private color getColorAt(Vector2D v) {
    final double x = v.getX();
    final double y = v.getY();
    if (x >= 0 && x < board.boardWidth && y >= 0 && y < board.boardHeight) {
      return board.tiles[(int)(x)][(int)(y)].getColor();
    } else {
      return board.BACKGROUND_COLOR;
    }
  }

  public void updateVision(Vector2D origin) {
    for (int k = 0; k < visionAngles.length; k++) {
      double visionTotalAngle = rotation + visionAngles[k];

      double endX = getVisionEndX(k);
      double endY = getVisionEndY(k);

      visionOccludedX[k] = endX;
      visionOccludedY[k] = endY;
      color c = getColorAt(endX, endY);
      visionResults[k * 3] = hue(c);
      visionResults[k * 3 + 1] = saturation(c);
      visionResults[k * 3 + 2] = brightness(c);

      int tileX = 0;
      int tileY = 0;
      int prevTileX = -1;
      int prevTileY = -1;
      ArrayList<SoftBody> potentialVisionOccluders = new ArrayList<SoftBody>();
      for (int DAvision = 0; DAvision < visionDistances[k] + 1; DAvision++) {
        tileX = (int)(visionStartX + Math.cos(visionTotalAngle) * DAvision);
        tileY = (int)(visionStartY + Math.sin(visionTotalAngle) * DAvision);
        if (tileX != prevTileX || tileY != prevTileY) {
          addPVOs(tileX, tileY, potentialVisionOccluders);
          if (prevTileX >= 0 && tileX != prevTileX && tileY != prevTileY) {
            addPVOs(prevTileX, tileY, potentialVisionOccluders);
            addPVOs(tileX, prevTileY, potentialVisionOccluders);
          }
        }
        prevTileX = tileX;
        prevTileY = tileY;
      }
      double[][] rotationMatrix = new double[2][2];
      rotationMatrix[1][1] = rotationMatrix[0][0] = Math.cos(-visionTotalAngle);
      rotationMatrix[0][1] = Math.sin(-visionTotalAngle);
      rotationMatrix[1][0] = -rotationMatrix[0][1];
      double visionLineLength = visionDistances[k];
      for (int i = 0; i < potentialVisionOccluders.size(); i++) {
        SoftBody body = potentialVisionOccluders.get(i);
        double x = body.px-px;
        double y = body.py-py;
        double r = body.getRadius();
        double translatedX = rotationMatrix[0][0] * x + rotationMatrix[1][0] * y;
        double translatedY = rotationMatrix[0][1] * x + rotationMatrix[1][1] * y;
        if (Math.abs(translatedY) <= r) {
          if ((translatedX >= 0 && translatedX < visionLineLength && translatedY < visionLineLength) ||
            distance(0, 0, translatedX, translatedY) < r ||
            distance(visionLineLength, 0, translatedX, translatedY) < r) { // YES! There is an occlussion.
            visionLineLength = translatedX-Math.sqrt(r * r - translatedY * translatedY);
            visionOccludedX[k] = visionStartX + visionLineLength * Math.cos(visionTotalAngle);
            visionOccludedY[k] = visionStartY + visionLineLength * Math.sin(visionTotalAngle);
            visionResults[k * 3] = body.hue;
            visionResults[k * 3 + 1] = body.saturation;
            visionResults[k * 3 + 2] = body.brightness;
          }
        }
      }
    }
  }
  
  public void addPVOs(Board board, int x, int y, ArrayList<SoftBody> PVOs) {
    if (x >= 0 && x < board.boardWidth && y >= 0 && y < board.boardHeight) {
      for (int i = 0; i < board.softBodiesInPositions[x][y].size(); i++) {
        SoftBody newCollider = (SoftBody)board.softBodiesInPositions[x][y].get(i);
        if (!PVOs.contains(newCollider) && newCollider != this) {
          PVOs.add(newCollider);
        }
      }
    }
  }
}