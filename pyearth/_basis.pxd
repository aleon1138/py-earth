from cpython cimport bool
cimport numpy as cnp
from _types cimport FLOAT_t, INT_t, INDEX_t, BOOL_t

cdef class BasisFunction:
    '''Abstract.  Subclasses must implement the apply and __init__ methods.'''

    cdef BasisFunction parent
    cdef dict child_map
    cdef list children
    cdef bint pruned
    cdef bint prunable
    cdef bint splittable

    cpdef smooth(BasisFunction self, dict knot_dict, dict translation)

    cpdef bint has_knot(BasisFunction self)

    cpdef bint is_prunable(BasisFunction self)

    cpdef bint is_pruned(BasisFunction self)

    cpdef bint is_splittable(BasisFunction self)

    cpdef bint make_splittable(BasisFunction self)

    cpdef bint make_unsplittable(BasisFunction self)

    cdef list get_children(BasisFunction self)

    cpdef _set_parent(BasisFunction self, BasisFunction parent)

    cpdef _add_child(BasisFunction self, BasisFunction child)

    cpdef BasisFunction get_parent(BasisFunction self)

    cpdef prune(BasisFunction self)

    cpdef unprune(BasisFunction self)

    cpdef knots(BasisFunction self, INDEX_t variable)

    cpdef INDEX_t degree(BasisFunction self)

    cpdef apply(BasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse= ?)

    cpdef cnp.ndarray[INT_t, ndim = 1] valid_knots(BasisFunction self,
        cnp.ndarray[FLOAT_t, ndim=1] values,
        cnp.ndarray[FLOAT_t, ndim=1] variable,
        int variable_idx, INDEX_t check_every,
        int endspan, int minspan,
        FLOAT_t minspan_alpha, INDEX_t n,
        cnp.ndarray[INT_t, ndim=1] workspace)

cdef class RootBasisFunction(BasisFunction):

    cpdef set variables(RootBasisFunction self)

    cpdef _smoothed_version(RootBasisFunction self, BasisFunction parent,
                            dict knot_dict, dict translation)

    cpdef INDEX_t degree(RootBasisFunction self)

    cpdef _set_parent(RootBasisFunction self, BasisFunction parent)

    cpdef BasisFunction get_parent(RootBasisFunction self)

    cpdef apply(RootBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse=?)

    cpdef apply_deriv(RootBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                      cnp.ndarray[FLOAT_t, ndim=1] b,
                      cnp.ndarray[FLOAT_t, ndim=1] j, INDEX_t var)

cdef class ConstantBasisFunction(RootBasisFunction):

    cpdef inline FLOAT_t eval(ConstantBasisFunction self)

    cpdef inline FLOAT_t eval_deriv(ConstantBasisFunction self)

cdef class VariableBasisFunction(BasisFunction):
    cdef INDEX_t variable

    cpdef set variables(VariableBasisFunction self)

    cpdef INDEX_t get_variable(VariableBasisFunction self)

    cpdef apply(VariableBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse=?)

    cpdef apply_deriv(VariableBasisFunction self,
                      cnp.ndarray[FLOAT_t, ndim=2] X,
                      cnp.ndarray[FLOAT_t, ndim=1] b,
                      cnp.ndarray[FLOAT_t, ndim=1] j, INDEX_t var)

cdef class HingeBasisFunctionBase(VariableBasisFunction):
    cdef FLOAT_t knot
    cdef INDEX_t knot_idx
    cdef bint reverse
    cdef str label

    cpdef bint has_knot(HingeBasisFunctionBase self)

    cpdef INDEX_t get_variable(HingeBasisFunctionBase self)

    cpdef FLOAT_t get_knot(HingeBasisFunctionBase self)

    cpdef bint get_reverse(HingeBasisFunctionBase self)

    cpdef INDEX_t get_knot_idx(HingeBasisFunctionBase self)

cdef class SmoothedHingeBasisFunction(HingeBasisFunctionBase):
    cdef FLOAT_t p
    cdef FLOAT_t r
    cdef FLOAT_t knot_minus
    cdef FLOAT_t knot_plus

    cpdef _smoothed_version(SmoothedHingeBasisFunction self,
                            BasisFunction parent, dict knot_dict,
                            dict translation)

    cpdef get_knot_minus(SmoothedHingeBasisFunction self)

    cpdef get_knot_plus(SmoothedHingeBasisFunction self)

    cpdef _init_p_r(SmoothedHingeBasisFunction self)

    cpdef get_p(SmoothedHingeBasisFunction self)

    cpdef get_r(SmoothedHingeBasisFunction self)

cdef class HingeBasisFunction(HingeBasisFunctionBase):

    cpdef _smoothed_version(HingeBasisFunction self,
                            BasisFunction parent,
                            dict knot_dict, dict translation)

cdef class LinearBasisFunction(VariableBasisFunction):
    cdef str label

    cpdef _smoothed_version(LinearBasisFunction self, BasisFunction parent,
                            dict knot_dict, dict translation)

    cpdef INDEX_t get_variable(self)

cdef class Basis:
    '''A wrapper that provides functionality related to a set of BasisFunctions
    with a common RootBasisFunction ancestor.  Retains the order in which
    BasisFunctions are added.'''

    cdef list order
    cdef readonly INDEX_t num_variables

    cpdef int get_num_variables(Basis self)

    cpdef dict anova_decomp(Basis self)

    cpdef smooth(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X)

    cpdef append(Basis self, BasisFunction basis_function)

    cpdef INDEX_t plen(Basis self)

    cpdef BasisFunction get(Basis self, INDEX_t i)

    cpdef transform(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                    cnp.ndarray[FLOAT_t, ndim=2] B)

    cpdef weighted_transform(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                             cnp.ndarray[FLOAT_t, ndim=2] B,
                             cnp.ndarray[FLOAT_t, ndim=1] weights)

    cpdef transform_deriv(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                          cnp.ndarray[FLOAT_t, ndim=1] b,
                          cnp.ndarray[FLOAT_t, ndim=1] j,
                          cnp.ndarray[FLOAT_t, ndim=1] coef,
                          cnp.ndarray[FLOAT_t, ndim=2] J,
                          list variables_of_interest, bool prezeroed_j=?)
