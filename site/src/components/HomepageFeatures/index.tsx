import type {ReactNode} from 'react';
import clsx from 'clsx';
import Heading from '@theme/Heading';
import styles from './styles.module.css';

type FeatureItem = {
  title: string;
  Svg: React.ComponentType<React.ComponentProps<'svg'>>;
  description: ReactNode;
};

const FeatureList: FeatureItem[] = [
  {
    title: 'Deploy and Manage your Favorite Kubernetes Packages',
    Svg: require('@site/static/img/simple.svg').default,
    description: (
      <>
          Browse and deploy packages from public and private registries.
            <br/>
          Perform day-two operations such as upgrades or rollbacks seamlessly.
      </>
    ),
  },
  {
    title: 'Use Private Namespaces and Multiple Clusters',
    Svg: require('@site/static/img/frictionless.svg').default,
    description: (
      <>
          Create and manage different catalogs isolating them in different namespaces and clusters just using a single Kubeapps instance.
      </>
    ),
  },
  {
    title: 'Secure Authentication and Authorization',
    Svg: require('@site/static/img/seamless.svg').default,
    description: (
      <>
          Leverage RBAC and OAuth2/OIDC to authenticate and authorize users in Kubeapps.
      </>
    ),
  },
];

function Feature({title, Svg, description}: FeatureItem) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center">
        <Svg className={styles.featureSvg} role="img" />
      </div>
      <div className="text--center padding-horiz--md">
        <Heading as="h3">{title}</Heading>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures(): ReactNode {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
