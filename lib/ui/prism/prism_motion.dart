import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Ported motion tokens & physics from FlClash / `prism_ui/lib/motion.dart`.
const Duration fadeTabDuration = Duration(milliseconds: 220);
const Curve fadeTabCurve = Curves.easeInOut;

/// iOS / FlClash droplet spring used for the floating navigation dock lens.
final SpringDescription dropletSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 165,
  ratio: 0.8,
);

/// Snappy spring used for tactile elastic press feedback.
final SpringDescription elasticPressSpring = SpringDescription.withDampingRatio(
  mass: 1,
  stiffness: 520,
  ratio: 0.72,
);

/// Critically damped spring matching `prism_ui/lib/page_transition.dart`.
final SpringDescription prismRouteSpring =
    SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 300),
);

/// Plays [spring] over the first [seconds] of an animation, easing out the
/// remaining residual so the curve still ends exactly at 1.
class SpringCurve extends Curve {
  SpringCurve(SpringDescription spring, {required this.seconds})
      : _simulation = SpringSimulation(spring, 0, 1, 0);

  final double seconds;
  final SpringSimulation _simulation;

  late final double _residual = 1 - _simulation.x(seconds);

  @override
  double transformInternal(double t) =>
      _simulation.x(t * seconds) + _residual * t;
}

/// Ends [simulation] at [end], where a controller would hold an overshoot.
class ArrivingSimulation extends Simulation {
  ArrivingSimulation(this.simulation, {required this.end})
      : _start = simulation.x(0),
        super(tolerance: simulation.tolerance);

  final Simulation simulation;
  final double end;
  final double _start;

  @override
  double x(double time) => simulation.x(time);

  @override
  double dx(double time) => simulation.dx(time);

  @override
  bool isDone(double time) =>
      simulation.isDone(time) ||
      (_start != end && (x(time) - end) * (_start - end) <= 0);
}

/// Rises to 1 at [peak] and back, as droplets overshoot and swell.
double riseAndFall(double time, double peak, double sharpness) {
  if (time <= 0) {
    return 0;
  }
  final x = time / peak;
  return math.pow(x, sharpness) * math.exp(sharpness * (1 - x));
}

/// Tactile spring scale press wrapper inspired by FlClash / `prism_ui`'s `ElasticPress`.
class PrismElasticPress extends StatefulWidget {
  const PrismElasticPress({
    super.key,
    required this.child,
    this.scaleDown = 0.965,
    this.enabled = true,
  });

  final Widget child;
  final double scaleDown;
  final bool enabled;

  @override
  State<PrismElasticPress> createState() => _PrismElasticPressState();
}

class _PrismElasticPressState extends State<PrismElasticPress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
  );

  void _animateTo(double target) {
    if (!widget.enabled || MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1.0;
      return;
    }
    _controller.animateWith(
      SpringSimulation(
        elasticPressSpring,
        _controller.value,
        target,
        _controller.velocity,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _animateTo(widget.scaleDown),
      onPointerUp: (_) => _animateTo(1.0),
      onPointerCancel: (_) => _animateTo(1.0),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final scale = _controller.value.clamp(0.88, 1.04);
          if ((scale - 1.0).abs() < 0.0005) {
            return child!;
          }
          return Transform.scale(
            scale: scale,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// FlClash / `prism_ui`-inspired critically damped spring push/pop page transition.
/// Slides incoming route in smoothly while softly receding and dimming the covered page.
class PrismPageTransitionsBuilder extends PageTransitionsBuilder {
  const PrismPageTransitionsBuilder();

  static final Curve _curve = SpringCurve(prismRouteSpring, seconds: 0.32);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (MediaQuery.disableAnimationsOf(context)) {
      return child;
    }

    final primary = CurvedAnimation(
      parent: animation,
      curve: _curve,
      reverseCurve: Curves.easeInCubic,
    );
    final secondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: _curve,
      reverseCurve: Curves.easeOutCubic,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([primary, secondary]),
      builder: (context, innerChild) {
        final enterOffset = Offset(1.0 - primary.value, 0.0);
        final exitOffset = Offset(-0.25 * secondary.value, 0.0);
        final dimAlpha = (0.08 * secondary.value).clamp(0.0, 0.12);

        Widget result = innerChild!;
        if (dimAlpha > 0.001) {
          result = ColorFiltered(
            colorFilter: ColorFilter.mode(
              Colors.black.withValues(alpha: dimAlpha),
              BlendMode.srcATop,
            ),
            child: result,
          );
        }
        return FractionalTranslation(
          translation: exitOffset,
          child: FractionalTranslation(
            translation: enterOffset,
            child: result,
          ),
        );
      },
      child: child,
    );
  }
}
