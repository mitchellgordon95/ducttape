package ducttape.hyperdag

import collection._
import collection.JavaConversions._
import java.util.concurrent._

import ducttape.Types._

// agenda-based DAG iterator that allows for parallelization
class PackedDagWalker[V](dag: PackedDag[V,_,_]) extends Walker[PackedVertex[V]] {

  private class ActiveVertex(val v: PackedVertex[V]) {
    assert(v != null)
    val filled = new Array[ActiveVertex](dag.inEdges(v).size)
    override def hashCode() = v.hashCode
    override def equals(that: Any) = that match { case other: ActiveVertex => (v == other.v) }
  }

  // taken and agenda must always be jointly locked when updating since if both are zero,
  // it means we're done
  private val active = new mutable.HashMap[PackedVertex[V],ActiveVertex]
                         with mutable.SynchronizedMap[PackedVertex[V],ActiveVertex]
  private val agenda = new ArrayBlockingQueue[ActiveVertex](dag.size)
  private val taken = new mutable.HashSet[ActiveVertex] with mutable.SynchronizedSet[ActiveVertex]
  private val completed = new mutable.HashSet[ActiveVertex] with mutable.SynchronizedSet[ActiveVertex]

  // first, visit the roots
  for(root <- dag.roots.iterator) {
    val actRoot = new ActiveVertex(root)
    agenda.offer(actRoot)
    active += root -> actRoot
  }

  def getCompleted(): Traversable[PackedVertex[V]] = for(act <- completed) yield act.v
  def getRunning(): Traversable[PackedVertex[V]] = for(act <- taken) yield act.v
  def getReady(): Traversable[PackedVertex[V]] = for(act <- agenda) yield act.v
//  def getBlocked(): Traversable[PackedVertex[P]] = 
  
  override def take(): Option[PackedVertex[V]] = {
    if(agenda.size == 0 && taken.size == 0) {
      return None
    } else {
      agenda.synchronized {
        val key: ActiveVertex = agenda.take
        taken += key
        Some(key.v)
      }
    }
  }

  override def complete(item: PackedVertex[V]) = {
    require(active.contains(item), "Cannot find active vertex for %s in %s".format(item, active))
    val key: ActiveVertex = active(item)

    // we always lock agenda & completed jointly
    agenda.synchronized {
      taken -= key
    }

    // first, match fronteir vertices
    for(consequent <- dag.children(key.v)) {
      val activeCon = active.getOrElseUpdate(consequent, new ActiveVertex(consequent))
      var allFilled = true
      val antecedents = dag.parents(consequent)
      for(i <- 0 until activeCon.filled.size) {
        if(key.v == antecedents(i)) {
          activeCon.filled(i) = key
        } else if(activeCon.filled(i) == null) {
          allFilled = false
        }
      }
      // this consequent has all its dependencies fulfilled
      if(allFilled) {
        agenda.synchronized {
          agenda.offer(activeCon)
        }
        // TODO: We could sort the agenda here to impose different objectives...
      }
    }

    // finally visit this vertex
    completed += key
  }
}
