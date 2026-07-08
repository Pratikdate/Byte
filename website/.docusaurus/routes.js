import React from 'react';
import ComponentCreator from '@docusaurus/ComponentCreator';

export default [
  {
    path: '/Byte/__docusaurus/debug',
    component: ComponentCreator('/Byte/__docusaurus/debug', '612'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/config',
    component: ComponentCreator('/Byte/__docusaurus/debug/config', 'e41'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/content',
    component: ComponentCreator('/Byte/__docusaurus/debug/content', 'b73'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/globalData',
    component: ComponentCreator('/Byte/__docusaurus/debug/globalData', 'a35'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/metadata',
    component: ComponentCreator('/Byte/__docusaurus/debug/metadata', '038'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/registry',
    component: ComponentCreator('/Byte/__docusaurus/debug/registry', '43c'),
    exact: true
  },
  {
    path: '/Byte/__docusaurus/debug/routes',
    component: ComponentCreator('/Byte/__docusaurus/debug/routes', '9d6'),
    exact: true
  },
  {
    path: '/Byte/docs',
    component: ComponentCreator('/Byte/docs', '87c'),
    routes: [
      {
        path: '/Byte/docs',
        component: ComponentCreator('/Byte/docs', 'c70'),
        routes: [
          {
            path: '/Byte/docs',
            component: ComponentCreator('/Byte/docs', '06d'),
            routes: [
              {
                path: '/Byte/docs/architecture',
                component: ComponentCreator('/Byte/docs/architecture', '24f'),
                exact: true,
                sidebar: "tutorialSidebar"
              }
            ]
          }
        ]
      }
    ]
  },
  {
    path: '*',
    component: ComponentCreator('*'),
  },
];
