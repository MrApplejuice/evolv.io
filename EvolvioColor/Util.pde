/**
  Yes, horrible name: The sink for all small classes that are used everywhere.
  
  Especially linear algebra stuff!
 */
 
 /**
   Helper class for transporting values outside the scope of 
   a local class defitinion.
  */
static class SettableDouble {
  public double value = 0;
};
 
 
static class Vector2D {
  private double[] components = {0, 0};
  
  protected Vector2D newVector() {
    return new Vector2D();
  }
  
  public double getX() {
    return components[0];
  }
  
  public double getY() {
    return components[1];
  }
  
  public Vector2D set(double x, double y) {
    components[0] = x;
    components[1] = y;
    return this;
  }
  
  public Vector2D set(Vector2D toCopy) {
    components[0] = toCopy.components[0];
    components[1] = toCopy.components[1];
    return this;
  }
  
  public Vector2D inplaceSub(Vector2D v) {
    components[0] -= v.components[0];
    components[1] -= v.components[1];
    return this;
  }
  
  public Vector2D inplaceAdd(Vector2D v) {
    components[0] += v.components[0];
    components[1] += v.components[1];
    return this;
  }
  
  public double dotProduct(Vector2D other) {
    return components[0] * other.components[0] + components[1] * other.components[1]; 
  }
  
  public double length() {
    return Math.sqrt(this.dotProduct(this));
  }

  public double distance(Vector2D other) {
    final Vector2D diff = this.newVector().set(other).inplaceSub(this);
    return diff.length();
  }
  
  @Override
  public boolean equals(Object other) {
    if (this == other) {
      return true;
    }
    if (Vector2D.class.isInstance(other)) {
      Vector2D ov = Vector2D.class.cast(other);
      return components[0] == ov.components[0] && components[1] == ov.components[1];
    }
    return false;
  }
}

static class Matrix2D {
  /**
    Flat vector with matrix components organized as follows:
     
     1 2
     3 4
   */
  private double[] components = {1, 0, 0, 1};
  
  protected Vector2D newVector2D() {
    return new Vector2D();
  }
  
  protected Matrix2D newMatrix2D() {
    return new Matrix2D();
  }
  
  public Matrix2D set(double m00, double m01, double m10, double m11) {
    components[0] = m00;
    components[1] = m01;
    components[2] = m10;
    components[3] = m11;
    return this;
  }
  
  public Matrix2D setRotationMatrix(double rotation) {
    final double sinR = Math.sin(rotation); 
    final double cosR = Math.cos(rotation);
    return set(cosR, -sinR, sinR, cosR);
  }
  
  public Matrix2D dotProduct(Matrix2D other) {
    return newMatrix2D().set(
      components[0] * other.components[0] + components[1] * other.components[2],
      components[0] * other.components[1] + components[1] * other.components[3],
      components[2] * other.components[0] + components[3] * other.components[2],
      components[2] * other.components[1] + components[3] * other.components[3]
    );
  }
  
  public Vector2D dotProduct(Vector2D v) {
    return newVector2D().set(
      components[0] * v.getX() + components[1] * v.getY(),
      components[2] * v.getX() + components[3] * v.getY()
    );
  }
}

/**
  Thread-safe pool to speed up vector interactions. Returned objects 
  are not thread safe though(!)
 */
static class LinearAlgebraPool {
  private ArrayList<Vector2D> vectors = new ArrayList<Vector2D>();
  private ArrayList<Matrix2D> matrices = new ArrayList<Matrix2D>();
  
  public synchronized Vector2D getVector2D() {
    if (vectors.size() > 0) {
      return vectors.remove(vectors.size() - 1);
    } else {
      // Constructs a special "pool-version" of the Vector2D
      return new Vector2D() {
        @Override
        protected Vector2D newVector() {
          return LinearAlgebraPool.this.getVector2D();
        }
        
        @Override
        public double distance(Vector2D other) {
          final Vector2D diff = this.newVector().set(other).inplaceSub(this);
          final double result = diff.length();
          recycle(diff);
          return result;
        }
      };
    }
  }
  
  public synchronized void recycle(Vector2D v) {
    if (v == null) {
      return;
    }
    v.set(0, 0); // Reset
    vectors.add(v);
  }
  
  public synchronized Matrix2D getMatrix2D() {
    if (matrices.size() > 0) {
      return matrices.remove(matrices.size() - 1);
    } else {
      // Constructs a special "pool-version" of the Vector2D
      return new Matrix2D() {
        @Override
        protected Vector2D newVector2D() {
          return LinearAlgebraPool.this.getVector2D();
        }
        
        @Override
        protected Matrix2D newMatrix2D() {
          return LinearAlgebraPool.this.getMatrix2D();
        }
      };
    }
  }
  
  public synchronized void recycle(Matrix2D v) {
    if (v == null) {
      return;
    }
    v.set(1, 0, 0, 1); // Reset
    matrices.add(v);
  }
}
 
LinearAlgebraPool globalLinAlgPool = new LinearAlgebraPool();