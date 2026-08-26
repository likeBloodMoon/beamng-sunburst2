// Sunburst2 Deluxe ECU tuning panel.
//
// This is the least-verified file in the whole mod: it can't be tested
// without a running BeamNG install, so the exact Angular app-registration
// details (manifest keys, streams API) are best-effort against long-stable
// BeamNG UI app conventions rather than something checked against a live
// game. If it fails to load, the vehicle Lua controllers underneath it
// still work fine on their own (edit the jbeam values directly) -- this
// panel is a convenience layer on top, not a dependency.

angular.module('beamng.apps')
.directive('sunburstDeluxeEcu', [function () {
  return {
    template:
      '<div class="sunburst-ecu-app">' +
        '<div class="title">Sunburst2 Deluxe ECU</div>' +
        '<div class="row"><span>RPM</span><span>{{rpm | number:0}}</span></div>' +
        '<div class="row"><span>Boost</span><span>{{boost | number:1}} psi</span></div>' +
        '<div class="row"><span>Status</span><span>{{indestructible ? "Indestructible" : "Normal"}}</span></div>' +
        '<hr/>' +
        '<div class="row"><span>Power Multiplier</span><span>x{{powerMult | number:1}}</span></div>' +
        '<input type="range" min="0.2" max="5" step="0.1" ng-model="powerMult" ng-change="applyPowerMult()"/>' +
        '<div class="row toggle">' +
          '<label><input type="checkbox" ng-model="indestructible" ng-change="applyIndestructible()"/> Indestructible</label>' +
        '</div>' +
        '<div class="row toggle">' +
          '<label><input type="checkbox" ng-model="bigBlock" ng-change="applyBigBlock()"/> Big Block Remap</label>' +
        '</div>' +
      '</div>',
    replace: true,
    restrict: 'EA',
    link: function (scope) {
      scope.rpm = 0
      scope.boost = 0
      scope.powerMult = 1
      scope.indestructible = false
      scope.bigBlock = false

      var streamsList = ['electrics']
      StreamsManager.add(streamsList)

      scope.$on('streamsUpdate', function (event, streams) {
        if (!streams || !streams.electrics) return
        var e = streams.electrics
        scope.rpm = e.rpm || 0
        scope.boost = e.boost || 0
        scope.indestructible = !!e.sunburstEcuIndestructible
      })

      function callEcu(method, arg) {
        if (window.bngApi && bngApi.activeObjectLua) {
          bngApi.activeObjectLua(
            "local c = controller.getController('sunburstDeluxeECU') " +
            "if c and c." + method + " then c." + method + "(" + arg + ") end"
          )
        }
      }

      scope.applyPowerMult = function () {
        callEcu('setPowerMultiplier', scope.powerMult)
      }
      scope.applyIndestructible = function () {
        callEcu('setIndestructible', scope.indestructible ? 'true' : 'false')
      }
      scope.applyBigBlock = function () {
        callEcu('setBigBlockRemap', scope.bigBlock ? 'true' : 'false')
      }

      scope.$on('$destroy', function () {
        StreamsManager.remove(streamsList)
      })
    }
  }
}])
