module.exports = {
  'env': {
    'es6': true,
    'node': true,
  },
  'parserOptions': {
    'ecmaVersion': 2018,
  },
  'extends': [
    'eslint:recommended',
    'google',
  ],
  'rules': {
    'no-restricted-globals': ['error', 'name', 'length'],
    'prefer-arrow-callback': 'error',
    'quotes': ['error', 'single', {'allowTemplateLiterals': true}],
    'max-len': ['error', {'code': 120}],
    'linebreak-style': 0,
  },
  'overrides': [
    {
      'files': ['**/*.spec.*'],
      'env': {
        'mocha': true,
      },
      'rules': {},
    },
  ],
  'globals': {},
};
