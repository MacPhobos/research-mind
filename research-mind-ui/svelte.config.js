import adapter from '@sveltejs/adapter-auto';

export default {
  kit: {
    adapter: adapter(),
    typescript: {
      config: (config) => {
        return config;
      },
    },
  },
};
