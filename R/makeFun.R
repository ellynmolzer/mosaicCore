utils::globalVariables(c('model', 'result'))

#' @importFrom stats formula predict coef
#' @importFrom dplyr tibble
NA


#' Create a function from a formula
#'
#' Provides an easy mechanism for creating simple "mathematical"
#' functions via a formula interface.
#'
#' @param object an object from which to create a function.  This should generally
#'         be specified without naming.
#' @param ... additional arguments in the form `var = val` that
#' set default values for the inputs to the function.
#' @return a function
#'
#' @details
#' The definition of the function is given by the left side of a formula.  The right
#' side lists at least one of the inputs to the function.
#' The inputs to the function are all variables appearing on either the left
#' or right sides of the formula.  Those appearing in the right side will
#' occur in the order specified.  Those not appearing in the right side will
#' appear in an unspecified order.
#'
#' @examples
#' f <- makeFun( sin(x^2 * b) ~ x & y & a); f
#' g <- makeFun( sin(x^2 * b) ~ x & y & a, a = 2 ); g
#' h <- makeFun( a * sin(x^2 * b) ~ b & y, a = 2, y = 3); h
#' @export

makeFun <- function(object, ...) {
  UseMethod("makeFun")
}

#' @rdname makeFun
#' @export

makeFun.function <-
  function( object, ..., strict.declaration  = TRUE, use.environment = TRUE,
            suppress.warnings = FALSE) {
    object
  }


#' @rdname makeFun
#' @param strict.declaration  if `TRUE` (the default), an error is thrown if
#' default values are given for variables not appearing in the `object` formula.
#' @param use.environment if `TRUE`, then variables implicitly defined in the
#' `object` formula can take default values from the environment at the time
#' `makeFun` is called.  A warning message alerts the user to this situation,
#' unless `suppress.warnings` is `TRUE`.
#' @param suppress.warnings A logical indicating whether warnings should be suppressed.
#' @param transformation a function used to transform the response.
#' This can be useful to invert a transformation used on the response
#' when creating the model.  If `NULL`, an attempt will be made to infer
#' the transformation from the model formula. A few simple transformations
#' (`log`, `log2`, `sqrt`) are recognized.  For other transformations,
#' `transformation` should be provided explicitly.
#' @details When creating a function from a model created with `lm`, `glm`, or `nls`,
#'   the function produced is a wrapper around the corresponding version of `predict`.
#'   This means that having variables in the model with names that match arguments of
#'   `predict` will lead to potentially ambiguous situations and should be avoided.
#' @examples
#' if (require(mosaicData)) {
#'   model <- lm( log(length) ~ log(width), data = KidsFeet)
#'   f <- makeFun(model, transformation = exp)
#'   f(8.4)
#'   head(KidsFeet, 1)
#' }
#'
#' @export

makeFun.formula <-
  function( object, ..., strict.declaration  = TRUE, use.environment = TRUE,
            suppress.warnings = TRUE) {
	  sexpr <- object
	  if (! inherits( sexpr, "formula") || length(sexpr) != 3)
		  stop('First argument must be a formula with both left and right sides.')

	  dots <- list(...)
	  expr <- eval(sexpr)  # not sure if eval() is needed here or not.
	  lhs <- lhs(expr) # expr[[2]]
	  rhs <- rhs(expr)  # expr[[3]]

	  rhsVars <- all.vars(rhs)
	  lhsOnlyVars <- setdiff(all.vars(lhs), rhsVars)
	  lhsOnlyVars <- setdiff(lhsOnlyVars, 'pi')    # don't treat pi like a variable
	  varsInFormula <- c(rhsVars, lhsOnlyVars)
    varsWithDefaults <- intersect( names(dots), varsInFormula )
    varsWithoutDefaults <- setdiff(varsInFormula, varsWithDefaults)
    varsFromEnv <- character(0)
	  # declaredVars <- union(varsInFormula, varsWithDefaults)  # unDeclaredVars)
	  undeclaredVars <- setdiff(names(dots), varsInFormula)
	  if (length( undeclaredVars ) != 0) {
		  if (strict.declaration)
		  	stop(paste( "Default values provided for variables not in formula:",
					   paste(undeclaredVars, collapse = ",")
					 ))
	  }
    # vars is just a permutation of varsInFormula
    vars <- c(varsWithoutDefaults, varsWithDefaults)
	  valVec <- rep("", length(vars))
	  names(valVec) <- vars

	  for( n in varsWithDefaults ) valVec[n] <- as.character(dots[[n]])

    if (use.environment) {
      for( n in setdiff(varsWithoutDefaults, rhsVars) ) {
        v <- tryCatch(get(n, parent.frame()), error = function(e) "")
        if (is.numeric(v)) {
          valVec[n] <- as.character(v)
          varsFromEnv <- c(varsFromEnv, n)
          varsWithoutDefaults <- setdiff(varsWithoutDefaults, n)
        }
      }
    }
    varsDangerous <- intersect(lhsOnlyVars, varsWithoutDefaults)
    varsWithoutDefaults <- setdiff(varsWithoutDefaults, varsDangerous)
    finalVars <- c(varsWithoutDefaults, varsWithDefaults, varsFromEnv, varsDangerous)
    # finalVars <- c(finalVars, setdiff(vars, finalVars))
    w <- which (valVec == "")
    if (length(varsFromEnv) > 0 & !suppress.warnings)
      warning(paste("Some default values taken from current environment: ",
                    paste(varsFromEnv, collapse = ", ") ))
	  if (length(varsDangerous) > 0 & !suppress.warnings)
	    warning(paste("Implicit variables without default values (dangerous!): ",
	                  paste(varsDangerous, collapse = ", ") ))

	  result <- function(...){}
	  body(result) <- parse( text = deparse(lhs) )
	  formals(result) <-
		 eval(parse(
			text = paste( "as.pairlist(alist(",
					paste(finalVars, "=", valVec[finalVars], collapse = ",", sep = ""), "))"
	  			)
	  ))
	  environment(result) <- environment(object) # parent.frame()
	  return(result)
  }

#' @rdname makeFun
#' @examples
#' if (require(mosaicData)) {
#'   model <- lm(wage ~ poly(exper, degree = 2), data = CPS85)
#'   fit <- makeFun(model)
#'   if (require(ggformula)) {
#'     gf_point(wage ~ exper, data = CPS85) %>%
#'     gf_fun(fit(exper) ~ exper, color = "red")
#'   }
#' }
#' @export

makeFun.lm <-
   function( object, ... , transformation = NULL) {
    if (is.null(transformation))  transformation <- infer_transformation(formula(object))
    dnames <- names(eval(object$call$data, parent.frame(1)))
	  vars <- modelVars(object)
    if (! is.null(dnames) ) vars <- intersect(vars, dnames)
	  result <- function(...){}
	  if ( length( vars ) <  1 ) {
		  result <- function(...) {
			  dots <- list(...)
			  if (length(dots) > 0) {
				  x <- dots[[1]]
			  } else {
				  x <- 1
			  }
			  dots <- dots[names(dots) != ""]
			  transformation( do.call(predict, c(list(model, newdata = data.frame(x = x)), dots)) )
		  }
	  } else {
		  body(result) <-
			  parse( text = paste(
								"return(transformation(predict(model, newdata = data.frame(",
								paste(vars, "= ", vars, collapse = ",", sep = ""),
								"), ...)))"
								)
		  )
		  args <- paste("alist(", paste(vars, " = ", collapse = ",", sep = ""), ")")
		  args <- eval(parse(text = args))
		  args['pi'] <- NULL
		  args <- c(args, alist('...' = ), list(transformation = substitute(transformation)))
		  formals(result) <- args
	  }

	  # myenv <- parent.frame()
	  # myenv$model <- object
	  # environment(result) <- myenv
	  environment(result) <- list2env( list(model = object, transformation = transformation) )
	  attr(result, "coefficients") <- coef(object)
	  return(result)
  }

#' @rdname makeFun
#' @param type one of `'response'` (default) or `'link'` specifying scale to be used
#' for value of function returned.
#' @examples
#' if (require(mosaicData)) {
#' model <- glm(wage ~ poly(exper, degree = 2), data = CPS85, family = gaussian)
#' fit <- makeFun(model)
#'   if (require(ggformula)) {
#'     gf_jitter(wage ~ exper, data = CPS85) %>%
#'     gf_fun(fit(exper) ~ exper, color = "red")
#'     gf_jitter(wage ~ exper, data = CPS85) %>%
#'     gf_function(fun = fit, color = "blue")
#'   }
#' }
#' @export

makeFun.glm <-
   function( object, ..., type = c('response', 'link'), transformation = NULL ) {
    if (is.null(transformation))
      transformation <- infer_transformation(formula(object), warn = FALSE)
	  type <- match.arg(type)
	  vars <- modelVars(object)
	  result <- function(...){}
	  if ( length( vars ) <  1 ) {
		  result <- function(...) {
			  dots <- list(...)
			  if (length(dots) > 0) {
				  x <- dots[[1]]
			  } else {
				  x <- 1
			  }
			  dots <- dots[names(dots) != ""]
			  transformation( do.call(predict, c(list(model, newdata = data.frame(x = x)), dots)) )
		  }
	  } else {
		  if (type == "link") {
		    body(result) <-
			  parse( text = paste(
								"return(transformation(predict(model, newdata = data.frame(",
								paste(vars, "= ", vars, collapse = ",", sep = ""),
								"), ..., type = 'link')))"
								) )
		  } else {
		    body(result) <-
			  parse( text = paste(
								"return(transformation(predict(model, newdata = data.frame(",
								paste(vars, "= ", vars, collapse = ",", sep = ""),
								"), ..., type = 'response')))"
								) )
		  }
		  args <- paste("alist(", paste(vars, " = ", collapse = ",", sep = ""), ")")
		  args <- eval(parse(text = args))
		  args['pi'] <- NULL
		  args <- c(args, alist('...' = ), list(transformation = substitute(transformation)))
		  formals(result) <- args

	  }

	  # myenv <- parent.frame()
	  # myenv$model <- object
	  # environment(result) <- myenv
	  environment(result) <- list2env( list(model = object, transformation = transformation) )
	  attr(result, "coefficients") <- coef(object)
	  return(result)
  }

#' @rdname makeFun
#' @examples
#' if (require(mosaicData)) {
#' model <- nls( wage ~ A + B * exper + C * exper^2, data = CPS85, start = list(A = 1, B = 1, C = 1) )
#' fit <- makeFun(model)
#'   if (require(ggformula)) {
#'     gf_point(wage ~ exper, data = CPS85) %>%
#'     gf_fun(fit(exper) ~ exper, color = "red")
#'   }
#' }
#'
#' @export

makeFun.nls <-
  function( object, ... , transformation = NULL) {
    if (is.null(transformation))  transformation <- infer_transformation(formula(object))
    dnames <- names(eval(object$call$data, parent.frame(1)))
    cvars <- names(coef(object))
    vars <- all.vars(rhs(eval(object$m$formula())))
    vars <- setdiff(vars, cvars)
    if (! is.null(dnames) ) vars <- intersect(vars, dnames)
    result <- function(...){}
    if ( length( vars ) <  1 ) {
      result <- function(...) {
        dots <- list(...)
        if (length(dots) > 0) {
          dots[[1]] <- NULL
        } else {
          x <- 1
        }
			  dots <- dots[names(dots) != ""]
        transformation( do.call(predict, c(list(model, newdata = data.frame(x = x)), dots)) )
      }
    } else {
      body(result) <-
        parse( text = paste(
          "return(transformation(predict(model, newdata = data.frame(",
          paste(vars, "= ", vars, collapse = ",", sep = ""),
          "), ...)))"
        )
        )
      # params <- as.list(coef(object))
      args <- paste("alist(", paste(vars, " = ", collapse = ",", sep = ""), ")")
      args <- eval(parse(text = args))
      # args <- c(args, params)
      args['pi'] <- NULL
      args <- c(args, alist('...' = ), list(transformation = substitute(transformation)))
      formals(result) <- args
    }

    environment(result) <- list2env( list(model = object, transformation = transformation) )
    attr(result, "coefficients") <- coef(object)
    return(result)
  }

#' extract predictor variables from a model
#'
#' @param model a model, typically of class `lm` or `glm`
#' @return a vector of variable names
#' @examples
#' if (require(mosaicData)) {
#'   model <- lm( wage ~ poly(exper, degree = 2), data = CPS85 )
#'   modelVars(model)
#' }
#' @export

modelVars <- function(model) {
  all.vars(rhs(model$terms))
}

#' Extract coefficients from a function
#'
#' `coef`  will extract the coefficients attribute from a function.
#' Functions created by applying \code{link{makeFun}} to a model produced
#' by [lm()], [glm()], or [nls()] store
#' the model coefficients there to enable this extraction.
#'
#' @name coef.function
#' @rdname coef
#' @aliases coef coef.function
#'
#' @param object a function
#' @param ... ignored
#'
#' @examples
#' if (require(mosaicData)) {
#'   model <- lm( width ~ length, data = KidsFeet)
#'   f <- makeFun( model )
#'   coef(f)
#' }
#' @export

coef.function <- function(object, ...) { attr(object, "coefficients") }

