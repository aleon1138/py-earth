# distutils: language = c
# cython: cdivision = True
# cython: boundscheck = False
# cython: wraparound = False
# cython: profile = False

from ._util cimport log2, apply_weights_2d
from libc.math cimport log
from libc.math cimport abs
cimport cython
cdef FLOAT_t ZERO_TOL = 1e-16
import numpy as np
import sys

cdef class BasisFunction:

    def __cinit__(BasisFunction self):
        self.pruned = False
        self.children = []
        self.prunable = True
        self.child_map = {}
        self.splittable = True

    def __hash__(BasisFunction self):
        return id(self) % sys.maxint # avoid "OverflowError Python
                                     # int too large to convert to C long"

    cpdef smooth(BasisFunction self, dict knot_dict, dict translation):
        '''
        Modifies translation in place.
        '''
        cdef INDEX_t i, n = len(self.children)
        translation[self] = self._smoothed_version(self.get_parent(), knot_dict,
                                                   translation)
        for i in range(n):
            self.children[i].smooth(knot_dict, translation)

    def __reduce__(BasisFunction self):
        return (self.__class__, (), self._getstate())

    def _get_root(BasisFunction self):
        return self.parent._get_root()

    def _getstate(BasisFunction self):
        result = {'pruned': self.pruned,
                  'children': self.children,
                  'prunable': self.prunable,
                  'child_map': self.child_map,
                  'splittable': self.splittable}
        result.update(self._get_parent_state())
        return result

    def _get_parent_state(BasisFunction self):
        return {'parent': self.parent}

    def _set_parent_state(BasisFunction self, state):
        self.parent = state['parent']

    def __setstate__(BasisFunction self, state):
        self.pruned = state['pruned']
        self.children = state['children']
        self.prunable = state['prunable']
        self.child_map = state['child_map']
        self.splittable = state['splittable']
        self._set_parent_state(state)

    def _eq(BasisFunction self, other):
        if self.__class__ is not other.__class__:
            return False
        self_state = (self._getstate(), self.__reduce__()[1])
        other_state = (other._getstate(), other.__reduce__()[1])
        del self_state[0]['children']
        del self_state[0]['child_map']
        del other_state[0]['children']
        del other_state[0]['child_map']
        return self_state == other_state

    def __richcmp__(BasisFunction self, other, method):
        if method == 2:
            return self._eq(other)
        elif method == 3:
            return not self._eq(other)
        else:
            return NotImplemented

    cpdef bint has_knot(BasisFunction self):
        return False

    cpdef bint is_prunable(BasisFunction self):
        return self.prunable

    cpdef bint is_pruned(BasisFunction self):
        return self.pruned

    cpdef bint is_splittable(BasisFunction self):
        return self.splittable

    cpdef bint make_splittable(BasisFunction self):
        self.splittable = True

    cpdef bint make_unsplittable(BasisFunction self):
        self.splittable = False

    cdef list get_children(BasisFunction self):
        return self.children

    cpdef _set_parent(BasisFunction self, BasisFunction parent):
        '''Calls _add_child.'''
        self.parent = parent
        self.parent._add_child(self)

    cpdef _add_child(BasisFunction self, BasisFunction child):
        '''Called by _set_parent.'''
        cdef INDEX_t n = len(self.children)
        self.children.append(child)
        cdef int var = child.get_variable()
        if var in self.child_map:
            self.child_map[var].append(n)
        else:
            self.child_map[var] = [n]

    cpdef BasisFunction get_parent(BasisFunction self):
        return self.parent

    cpdef prune(BasisFunction self):
        self.pruned = True

    cpdef unprune(BasisFunction self):
        self.pruned = False

    cpdef knots(BasisFunction self, INDEX_t variable):

        cdef list children
        cdef BasisFunction child
        if variable in self.child_map:
            children = self.child_map[variable]
        else:
            return []
        cdef INDEX_t n = len(children)
        cdef INDEX_t i
        cdef list result = []
        cdef int idx
        for i in range(n):
            idx = children[i]
            child = self.get_children()[idx]
            if child.has_knot():
                result.append(child.get_knot_idx())
        return result

    cpdef INDEX_t degree(BasisFunction self):
        return self.parent.degree() + 1

    cpdef apply(BasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse=True):
        '''
        X - Data matrix
        b - parent vector
        recurse - If False, assume b already contains the result of
        the parent function.  Otherwise, recurse to compute parent function.
        '''

    cpdef cnp.ndarray[INT_t, ndim = 1] valid_knots(BasisFunction self,
        cnp.ndarray[FLOAT_t, ndim=1] values,
        cnp.ndarray[FLOAT_t, ndim=1] variable, int variable_idx,
        INDEX_t check_every,
        int endspan, int minspan,
        FLOAT_t minspan_alpha, INDEX_t n,
        cnp.ndarray[INT_t, ndim=1] workspace):
        '''
        values - The unsorted values of self in the data set
        variable - The sorted values of variable in the data set
        variable_idx - The index of the variable in the data set
        workspace - An m-vector (where m is the number of samples) used
                    internally
        '''
        cdef INDEX_t i
        cdef INDEX_t j
        cdef INDEX_t k
        cdef INDEX_t m = values.shape[0]
        cdef FLOAT_t float_tmp
        cdef INT_t int_tmp
        cdef INDEX_t count
        cdef int minspan_
        cdef cnp.ndarray[INT_t, ndim = 1] result
        cdef INDEX_t num_used
        cdef INDEX_t prev
        cdef INDEX_t start
        cdef int idx
        cdef int last_idx
        cdef FLOAT_t first_var_value = variable[m - 1]
        cdef FLOAT_t last_var_value = variable[m - 1]

        # Calculate the used knots
        cdef list used_knots = self.knots(variable_idx)
        used_knots.sort()

        # Initialize workspace to 1 where value is nonzero
        # Also, find first_var_value as the maximum variable
        # where value is nonzero and last_var_value to the
        # minimum variable where value is nonzero
        count = 0
        for i in range(m):
            if abs(values[i]) > ZERO_TOL:
                workspace[i] = 1
                count += 1
                if variable[i] >= first_var_value:
                    first_var_value = variable[i]
                last_var_value = variable[i]
            else:
                workspace[i] = 0

        # Calculate minspan
        if minspan < 0:
            minspan_ = <int > (-log2(-(1.0 / (n * count)) *
                                log(1.0 - minspan_alpha)) / 2.5)
        else:
            minspan_ = minspan

        # Take out the used points and apply minspan
        num_used = len(used_knots)
        prev = 0
        last_idx = -1
        for i in range(num_used):
            idx = used_knots[i]
            if last_idx == idx:
                continue
            workspace[idx] = 0
            j = idx
            k = 0
            while j > prev + 1 and k < minspan_:
                if workspace[j - 1]:
                    workspace[j - 1] = False
                    k += 1
                j -= 1
            j = idx + 1
            k = 0
            while j < m and k < minspan_:
                if workspace[j]:
                    workspace[j] = False
                    k += 1
                j += 1
            prev = idx
            last_idx = idx

        # Apply endspan
        i = 0
        j = 0
        while i < endspan:
            if workspace[j]:
                workspace[j] = 0
                i += 1
            j += 1
            if j == m:
                break
        i = 0
        j = m - 1
        while i < endspan:
            if workspace[j]:
                workspace[j] = 0
                i += 1
            if j == 0:
                break
            j -= 1

        # Implement check_every
        int_tmp = 0
        count = 0
        for i in range(m):
            if workspace[i]:
                if (int_tmp % check_every) != 0:
                    workspace[i] = 0
                else:
                    count += 1
                int_tmp += 1
            else:
                int_tmp = 0

        # Make sure the greatest value is not a candidate (this can happen if
        # the first endspan+1 values are the same)
        for i in range(m):
            if workspace[i]:
                if variable[i] == first_var_value:
                    workspace[i] = 0
                    count -= 1
                else:
                    break

        # Also make sure the least value is not a candidate
        for i in range(m):
            if workspace[m - i - 1]:
                if variable[m - i - 1] == last_var_value:
                    workspace[m - i - 1] = 0
                    count -= 1
                else:
                    break

        # Create result array and return
        result = np.empty(shape=count, dtype=int)
        j = 0
        for i in range(m):
            if workspace[i]:
                result[j] = i
                j += 1

        return result

cdef class PicklePlaceHolderBasisFunction(BasisFunction):
    '''This is a place holder for unpickling the basis function tree.'''

pickle_place_holder = PicklePlaceHolderBasisFunction()

cdef class RootBasisFunction(BasisFunction):
    def __init__(RootBasisFunction self):  # @DuplicatedSignature
        self.prunable = False

    def copy(RootBasisFunction self):
        return self.__class__()

    def _get_root(RootBasisFunction self):  # @DuplicatedSignature
        return self

    def _get_parent_state(RootBasisFunction self):  # @DuplicatedSignature
        return {}

    def _set_parent_state(RootBasisFunction self, state): # @DuplicatedSignature
        pass

    cpdef set variables(RootBasisFunction self):
        return set()

    cpdef _smoothed_version(RootBasisFunction self, BasisFunction parent,
                            dict knot_dict, dict translation):
        result = self.__class__()
        if self.is_pruned():
            result.prune()
        return result

    cpdef INDEX_t degree(RootBasisFunction self):
        return 0

    cpdef _set_parent(RootBasisFunction self, BasisFunction parent):
        raise NotImplementedError

    cpdef BasisFunction get_parent(RootBasisFunction self):
        return None

    cpdef apply(RootBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse=False):
        '''
        X - Data matrix
        b - parent vector
        recurse - The ZeroBasisFunction is an alternative RootBasisFunction used
                  for computing derivatives.
        It is the derivative of the ConstantBasisFunction.
        '''
        b[:] = self.eval()

    cpdef apply_deriv(RootBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                      cnp.ndarray[FLOAT_t, ndim=1] b,
                      cnp.ndarray[FLOAT_t, ndim=1] j, INDEX_t var):
        '''
        X - Data matrix
        b - holds the value of the basis function
        j - holds the value of the derivative
        '''
        b[:] = self.eval()
        j[:] = self.eval_deriv()

@cython.final
cdef class ConstantBasisFunction(RootBasisFunction):

    cpdef inline FLOAT_t eval(ConstantBasisFunction self):
        return <FLOAT_t> 1.0

    cpdef inline FLOAT_t eval_deriv(ConstantBasisFunction self):
        return <FLOAT_t> 0.0

    def __str__(ConstantBasisFunction self):
        return '(Intercept)'

cdef class VariableBasisFunction(BasisFunction):
    cpdef set variables(VariableBasisFunction self):
        cdef set result = self.parent.variables()
        result.add(self.get_variable())
        return result

    cpdef INDEX_t get_variable(VariableBasisFunction self):
        return self.variable

    cpdef apply(VariableBasisFunction self, cnp.ndarray[FLOAT_t, ndim=2] X,
                cnp.ndarray[FLOAT_t, ndim=1] b, bint recurse=True):
        '''
        X - Data matrix
        b - parent vector
        recurse - If False, assume b already contains the result of the parent
                  function.  Otherwise, recurse to compute parent function.
        '''
        if recurse:
            self.parent.apply(X, b, recurse=True)
        b *= self.eval(X[:, self.variable])

    cpdef apply_deriv(VariableBasisFunction self,
                      cnp.ndarray[FLOAT_t, ndim=2] X,
                      cnp.ndarray[FLOAT_t, ndim=1] b,
                      cnp.ndarray[FLOAT_t, ndim=1] j, INDEX_t var):
        '''
        X - Data matrix
        j - result vector
        '''
        cdef INDEX_t i, this_var = self.get_variable()  # @DuplicatedSignature
        cdef INDEX_t m = len(b)  # @DuplicatedSignature
        cdef FLOAT_t x
        self.parent.apply_deriv(X, b, j, var)
        this_val = self.eval(X[:,this_var])
        this_deriv = self.eval_deriv(X[:,this_var])
        for i in range(m):
            x = X[i,this_var]
            j[i] = j[i]*this_val[i]
            if this_var == var:
                j[i] += b[i]*this_deriv[i]
            b[i] *= this_val[i]

cdef class HingeBasisFunctionBase(VariableBasisFunction):
    cpdef bint has_knot(HingeBasisFunctionBase self):
        return True

    cpdef FLOAT_t get_knot(HingeBasisFunctionBase self):
        return self.knot

    cpdef bint get_reverse(HingeBasisFunctionBase self):
        return self.reverse

    cpdef INDEX_t get_knot_idx(HingeBasisFunctionBase self):
        return self.knot_idx

@cython.final
cdef class SmoothedHingeBasisFunction(HingeBasisFunctionBase):

    def __init__(SmoothedHingeBasisFunction self, BasisFunction parent,
                 FLOAT_t knot, FLOAT_t knot_minus,
                 FLOAT_t knot_plus, INDEX_t knot_idx,
                 INDEX_t variable, bint reverse,
                 label=None):
        self.knot = knot
        self.knot_minus= knot_minus
        self.knot_plus = knot_plus
        self.knot_idx = knot_idx
        self.variable = variable
        self.reverse = reverse
        self.label = label if label is not None else 'x' + str(variable)
        self._set_parent(parent)
        self._init_p_r()

    cpdef get_knot_minus(SmoothedHingeBasisFunction self):
        return self.knot_minus

    cpdef get_knot_plus(SmoothedHingeBasisFunction self):
        return self.knot_plus

    cpdef _smoothed_version(SmoothedHingeBasisFunction self,
                            BasisFunction parent, dict knot_dict,
                            dict translation):
        result = SmoothedHingeBasisFunction(translation[parent], self.knot,
                                            self.knot_minus, self.knot_plus,
                                            self.knot_idx, self.variable,
                                            self.reverse)
        if self.is_pruned():
            result.prune()
        return result

    cpdef _init_p_r(SmoothedHingeBasisFunction self):
        # See Friedman, 1991, eq (35)
        cdef FLOAT_t p_denom = self.knot_plus - self.knot_minus
        cdef FLOAT_t r_denom = p_denom
        p_denom *= p_denom
        r_denom *= p_denom
        if not self.reverse:
            self.p = (2*self.knot_plus + self.knot_minus - 3*self.knot) / p_denom
            self.r = (2*self.knot - self.knot_plus - self.knot_minus) / r_denom
        else:
            self.p = (3*self.knot - 2*self.knot_minus - self.knot_plus) / p_denom
            self.r = -1*(self.knot_minus + self.knot_plus - 2*self.knot) / r_denom

    cpdef get_p(SmoothedHingeBasisFunction self):
        return self.p

    cpdef get_r(SmoothedHingeBasisFunction self):
        return self.r

    def __str__(SmoothedHingeBasisFunction self):  # @DuplicatedSignature
        result = ''
        if self.variable is not None:
            if not self.reverse:
                result = 'C(%s|s=+1,%G,%G,%G)' % (self.label, self.knot_minus,
                                                  self.knot, self.knot_plus)
            else:
                result = 'C(%s|s=-1,%G,%G,%G)' % (self.label, self.knot_minus,
                                                  self.knot, self.knot_plus)
        parent = (str(self.parent)
                  if not self.parent.__class__ is ConstantBasisFunction
                  else '')
        if parent != '':
            result += '*%s' % (str(self.parent),)
        return result

    def __reduce__(SmoothedHingeBasisFunction self):  # @DuplicatedSignature
        return (self.__class__,
                (pickle_place_holder, self.knot,
                 self.knot_minus, self.knot_plus,
                 self.knot_idx, self.variable, self.reverse, self.label),
                self._getstate())

    def eval(SmoothedHingeBasisFunction self, x):
        # See Friedman, 1991, eq (34)
        if not self.reverse:
            tmp2 = x - self.knot_minus
            return np.where(x <= self.knot_minus, 0.0,
                np.where((self.knot_minus < x) & (x < self.knot_plus),
                    self.p*tmp2**2 + self.r*tmp2**3, x - self.knot))
        else:
            tmp2 = x - self.knot_plus
            return np.where(x <= self.knot_minus, self.knot - x,
                np.where((self.knot_minus < x) & (x < self.knot_plus),
                    self.p*tmp2**2 + self.r*tmp2**3, 0.0))

    def eval_deriv(SmoothedHingeBasisFunction self, x):
        # See Friedman, 1991, eq (34)
        if not self.reverse:
            tmp2 = x - self.knot_minus
            return np.where(x <= self.knot_minus, 0.0,
                np.where((self.knot_minus < x) & (x < self.knot_plus),
                    2.0*self.p*tmp2 + 3.0*self.r*tmp2**2, 1.0))
        else:
            tmp2 = x - self.knot_plus
            return np.where(x <= self.knot_minus, -1.0,
                np.where((self.knot_minus < x) & (x < self.knot_plus),
                    2.0*self.p*tmp2 + 3.0*self.r*tmp2**2, 0.0))

@cython.final
cdef class HingeBasisFunction(HingeBasisFunctionBase):

    def __init__(HingeBasisFunction self, BasisFunction parent, FLOAT_t knot,
                 INDEX_t knot_idx, INDEX_t variable, bint reverse, label=None):
        self.knot = knot
        self.knot_idx = knot_idx
        self.variable = variable
        self.reverse = reverse
        self.label = label if label is not None else 'x' + str(variable)
        self._set_parent(parent)

    cpdef _smoothed_version(HingeBasisFunction self, BasisFunction parent,
                            dict knot_dict, dict translation):
        knot_minus, knot_plus = knot_dict[self]
        result = SmoothedHingeBasisFunction(translation[parent], self.knot,
                                            knot_minus, knot_plus,
                                            self.knot_idx, self.variable,
                                            self.reverse)
        if self.is_pruned():
            result.prune()
        return result

    def __reduce__(HingeBasisFunction self):
        return (self.__class__,
                ( pickle_place_holder, self.knot, self.knot_idx,
                  self.variable, self.reverse, self.label),
                self._getstate())

    def __str__(HingeBasisFunction self):
        result = ''
        if self.variable is not None:
            if not self.reverse:
                if self.knot >= 0:
                    result = 'h(%s-%G)' % (self.label, self.knot)
                else:
                    result = 'h(%s+%G)' % (self.label, -self.knot)
            else:
                result = 'h(%G-%s)' % (self.knot, self.label)
        parent = (str(self.parent)
                  if not self.parent.__class__ is ConstantBasisFunction
                  else '')
        if parent != '':
            result += '*%s' % (str(self.parent),)
        return result

    def eval(HingeBasisFunction self, x):
        if self.reverse:
            return np.where(x  > self.knot, 0.0, self.knot - x)
        else:
            return np.where(x <= self.knot, 0.0, x - self.knot)

    def eval_deriv(HingeBasisFunction self, x):
        if self.reverse:
            return np.where(x  > self.knot, 0.0, -1.0)
        else:
            return np.where(x <= self.knot, 0.0,  1.0)

@cython.final
cdef class LinearBasisFunction(VariableBasisFunction):
    #@DuplicatedSignature
    def __init__(LinearBasisFunction self, BasisFunction parent,
                 INDEX_t variable, label=None):
        self.variable = variable
        self.label = label if label is not None else 'x' + str(variable)
        self._set_parent(parent)

    cpdef _smoothed_version(LinearBasisFunction self, BasisFunction parent,
                            dict knot_dict, dict translation):
        result = LinearBasisFunction(translation[parent], self.variable,
                                     self.label)
        if self.is_pruned():
            result.prune()
        return result

    def __reduce__(LinearBasisFunction self):
        return (self.__class__,
                (pickle_place_holder, self.variable, self.label),
                self._getstate())

    def __str__(LinearBasisFunction self):
        result = self.label
        if not self.parent.__class__ is ConstantBasisFunction:
            parent = str(self.parent)
            result += '*' + parent
        return result

    cpdef INDEX_t get_variable(LinearBasisFunction self):
        return self.variable

    def eval(LinearBasisFunction self, x):
        return x

    def eval_deriv(LinearBasisFunction self, x):
        return np.ones(len(x))

cdef class Basis:
    '''A container that provides functionality related to a set of
    BasisFunctions with a common ConstantBasisFunction ancestor.
    Retains the order in which BasisFunctions are added.'''

    def __init__(Basis self, num_variables):  # @DuplicatedSignature
        self.order = []
        self.num_variables = num_variables

    def __reduce__(Basis self):
        return (self.__class__, (self.num_variables,), self._getstate())

    def _getstate(Basis self):
        return {'order': self.order}

    def __setstate__(Basis self, state):
        self.order = state['order']

    def __richcmp__(Basis self, other, method):
        if method == 2:
            return self._eq(other)
        elif method == 3:
            return not self._eq(other)
        else:
            return NotImplemented

    def _eq(Basis self, other):
        return (self.__class__ is other.__class__ and
                self._getstate() == other._getstate())

    def piter(Basis self):
        for bf in self.order:
            if not bf.is_pruned():
                yield bf

    def __str__(Basis self):
        cdef INDEX_t i
        cdef INDEX_t n = len(self)
        result = ''
        for i in range(n):
            result += str(self[i])
            result += '\n'
        return result

    cpdef int get_num_variables(Basis self):
        return self.num_variables

    cpdef dict anova_decomp(Basis self):
        '''
        See section 3.5, Friedman, 1991
        '''
        cdef INDEX_t bf_idx, n_bf = len(self)
        cdef dict result = {}
        cdef frozenset vars
        cdef BasisFunction bf
        for bf_idx in range(n_bf):
            bf = self.order[bf_idx]
            vars = frozenset(bf.variables())
            if vars in result:
                result[vars].append(bf)
            else:
                result[vars] = [bf]
        return result

    def smooth_knots(Basis self, mins, maxes):
        '''
        Used to find the side knots in the smoothed representation.
        '''
        cdef dict anova = self.anova_decomp()
        cdef dict intermediate = {}
        cdef dict result = {}
        for vars, bfs in anova.iteritems():
            intermediate[vars] = {}
            for var in vars:
                intermediate[vars][var] = []
            for bf in bfs:
                if bf.has_knot():
                    variable = bf.get_variable()
                    knot = bf.get_knot()
                    intermediate[vars][variable].append((bf, knot))
        for d in intermediate.itervalues():
            for var, lst in d.iteritems():
                lst.sort(key=lambda x: x[1])
                prev_minus = mins[var]
                prev = prev_minus
                prev_mid = prev_minus
                plus_idx = 0
                i = 0
                n_bfs = len(lst)
                while True:
                    if i >= n_bfs:
                        break
                    bf, knot = lst[i]
                    if knot > prev_mid:
                        prev = prev_mid
                    else:
                        prev = prev_minus
                    while plus_idx < n_bfs and lst[plus_idx][1] <= knot:
                        plus_idx += 1
                    if plus_idx < n_bfs and lst[plus_idx][1] > knot:
                        next = lst[plus_idx][1]
                    else:
                        next = maxes[var]
                    result[bf] = ((knot + prev) / 2.0, (knot + next) / 2.0)
                    prev_minus = prev
                    prev_mid = knot
                    i += 1
        return result

    cpdef smooth(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X):
        mins = list(X.min(0))
        maxes = list(X.max(0))
        knot_dict = self.smooth_knots(mins, maxes)
        root = self[0]._get_root()
        translation_dict = {}
        root.smooth(knot_dict, translation_dict)
        new_order = [translation_dict[bf] for bf in self]
        result = Basis(self.num_variables)
        for bf in new_order:
            result.append(bf)
        return result

    cpdef append(Basis self, BasisFunction basis_function):
        self.order.append(basis_function)

    def __iter__(Basis self):
        return self.order.__iter__()

    def __len__(Basis self):
        return self.order.__len__()

    cpdef BasisFunction get(Basis self, INDEX_t i):
        return self.order[i]

    def __getitem__(Basis self, INDEX_t i):
        return self.get(i)

    cpdef INDEX_t plen(Basis self):
        cdef INDEX_t length = 0
        for bf in self.order:
            if not bf.is_pruned():
                length += 1
        return length

    cpdef transform(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                    cnp.ndarray[FLOAT_t, ndim=2] B):
        cdef BasisFunction bf
        cdef INDEX_t col = 0
        for bf in self.order:
            if not bf.is_pruned():
                bf.apply(X, B[:, col], recurse=True)
                col += 1

    cpdef weighted_transform(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                             cnp.ndarray[FLOAT_t, ndim=2] B,
                             cnp.ndarray[FLOAT_t, ndim=1] weights):
        self.transform(X, B)
        apply_weights_2d(B, weights)

    cpdef transform_deriv(Basis self, cnp.ndarray[FLOAT_t, ndim=2] X,
                          cnp.ndarray[FLOAT_t, ndim=1] b,
                          cnp.ndarray[FLOAT_t, ndim=1] j,
                          cnp.ndarray[FLOAT_t, ndim=1] coef,
                          cnp.ndarray[FLOAT_t, ndim=2] J,
                          list variables_of_interest, bool prezeroed_j=False):

        cdef BasisFunction bf
        cdef INDEX_t i, j_, m, n

        # Zero out J if necessary
        m = J.shape[0]
        n = J.shape[1]
        if not prezeroed_j:
            for j_ in range(n):
                for i in range(m):
                    J[i, j_] = 0.0

        # Compute the derivative for each variable
        cdef INDEX_t var, bf_idx, coef_idx, n_bfs = len(self)
        cdef set variables
        for j_, var in enumerate(variables_of_interest):
            coef_idx=0
            for bf_idx in range(n_bfs):
                bf = self.order[bf_idx]
                variables = bf.variables()
                if (variables and var not in variables) or bf.is_pruned():
                    continue
                bf.apply_deriv(X, b, j, var)
                for i in range(m):
                    J[i, j_] += coef[coef_idx] * j[i]
                coef_idx += 1


