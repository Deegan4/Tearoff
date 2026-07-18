module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
    plugins: [
      // react-native-worklets/reanimated must be the last plugin.
      'react-native-worklets/plugin',
    ],
  };
};
