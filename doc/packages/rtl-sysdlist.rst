Package: src/packages/rtl-sysdlist.fdoc


========
Sysdlist
========

================ ===============================
key              file                            
================ ===============================
flx_sysdlist.cpp share/src/rtl/flx_sysdlist.cpp  
flx_sysdlist.hpp share/lib/rtl/flx_sysdlist.hpp  
sysdlist.flx     share/lib/datatype/sysdlist.flx 
================ ===============================


Double linked list of pointers
==============================

Not used any more.


.. code-block:: cpp

  //[flx_sysdlist.hpp]
  #ifndef __FLX_SYSDLIST_H__
  #define __FLX_SYSDLIST_H__
  #include "flx_rtl_config.hpp"
  #include "flx_gc.hpp"
  
  #include <list>
  
  namespace flx { namespace rtl {
  
  struct RTL_EXTERN sysdlist_t {
    sysdlist_t();
    ::std::list<void*> data;
  };
  
  RTL_EXTERN extern ::flx::gc::generic::scanner_t scan_sysdlist;
  RTL_EXTERN extern ::flx::gc::generic::gc_shape_t sysdlist_t_ptr_map;
  
  
  }}
  #endif


.. code-block:: cpp

  //[flx_sysdlist.cpp]
  #include "flx_sysdlist.hpp"
  
  namespace flx { namespace rtl {
  sysdlist_t::sysdlist_t () {}
  
  void *scan_sysdlist(
    ::flx::gc::generic::collector_t *collector, 
    ::flx::gc::generic::gc_shape_t *shape, 
    void *p, 
    size_t dyncount, 
    int reclimit
  )
  {
    auto q = reinterpret_cast<::flx::rtl::sysdlist_t*>(p);
  
    // calculate the absolute number of used array slots
    size_t n_used = dyncount  * shape->count;
    for (size_t j=0; j<n_used; ++j) 
      for (auto elt  : q->data) 
        if (collector->inrange(elt))
          collector->register_pointer (elt, reclimit -1);
    return nullptr;
  }
  // ********************************************************
  // SHAPE for sysdlist_t 
  // ********************************************************
  
  ::flx::gc::generic::gc_shape_t sysdlist_t_ptr_map = {
    "rtl::sysdlist_t",
    1,sizeof(sysdlist_t),
    0, // no finaliser,
    0, // fcops
    0, // no offset data
    scan_sysdlist,
    0,0, // no serialisation as yet
    ::flx::gc::generic::gc_flags_default,
    0UL, 0UL
  };
  }}
  


Sysdlist 
=========

Doubly linked gc aware list of adresses.

.. index:: SysDlist(class)
.. index:: push_front(proc)
.. index:: push_back(proc)
.. index:: front(fun)
.. index:: pop_front(gen)
.. index:: unsafe_pop_front(gen)
.. index:: empty(fun)
.. index:: len(fun)
.. code-block:: felix

  //[sysdlist.flx]
  class SysDlist {
    _gc_pointer type sysdlist[T] = "::flx::rtl::sysdlist_t*";
    ctor[T] sysdlist[T] : 1 = "new (*(ptf->gcp), ::flx::rtl::sysdlist_t_ptr_map, true) ::flx::rtl::sysdlist_t()";
    proc push_front[T] : sysdlist[T] * &T = "$1->data.push_front((void*)$2);";
    proc push_back[T]: sysdlist[T] * &T = "$1->data.push_front((void*)$2);";
    fun front[T]: sysdlist[T]  -> &T = "(?1*)$1->data.front();";
    gen pop_front[T]: sysdlist[T] -> @T = """
    (?1*)(
      ([&] () 
      { 
        if ($1->data.empty()) return (void*)nullptr; 
        auto x = $1->data.front(); 
        $1->data.pop_front(); 
        return x; 
      })
      ()
    )""";
  
    gen unsafe_pop_front[T](x:sysdlist[T]): &T => C_hack::cast[&T](pop_front x);
  
    fun empty[T]: sysdlist[T] -> bool = "$1->data.empty()";
    fun len[T]: sysdlist[T] -> size = "$1->data.size()";
  }
  


