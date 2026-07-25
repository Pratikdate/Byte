import React from 'react';
import ComponentCreator from '@docusaurus/ComponentCreator';

export default [
  {
    path: '/Byte/markdown-page',
    component: ComponentCreator('/Byte/markdown-page', 'fb2'),
    exact: true
  },
  {
    path: '/Byte/docs',
    component: ComponentCreator('/Byte/docs', '72e'),
    routes: [
      {
        path: '/Byte/docs',
        component: ComponentCreator('/Byte/docs', '7be'),
        routes: [
          {
            path: '/Byte/docs',
            component: ComponentCreator('/Byte/docs', '8ef'),
            routes: [
              {
                path: '/Byte/docs/architecture',
                component: ComponentCreator('/Byte/docs/architecture', '24f'),
                exact: true,
                sidebar: "tutorialSidebar"
              },
              {
                path: '/Byte/docs/behaviors',
                component: ComponentCreator('/Byte/docs/behaviors', '824'),
                exact: true,
                sidebar: "tutorialSidebar"
              },
              {
                path: '/Byte/docs/empathy-ml-pipeline',
                component: ComponentCreator('/Byte/docs/empathy-ml-pipeline', 'f6d'),
                exact: true,
                sidebar: "tutorialSidebar"
              },
              {
                path: '/Byte/docs/installation-guide',
                component: ComponentCreator('/Byte/docs/installation-guide', '75a'),
                exact: true,
                sidebar: "tutorialSidebar"
              },
              {
                path: '/Byte/docs/sensors-and-os',
                component: ComponentCreator('/Byte/docs/sensors-and-os', '082'),
                exact: true,
                sidebar: "tutorialSidebar"
              },
              {
                path: '/Byte/docs/state-engine',
                component: ComponentCreator('/Byte/docs/state-engine', '743'),
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
    path: '/Byte/',
    component: ComponentCreator('/Byte/', '716'),
    exact: true
  },
  {
    path: '*',
    component: ComponentCreator('*'),
  },
];
